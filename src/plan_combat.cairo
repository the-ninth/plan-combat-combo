use starknet::{ContractAddress, ClassHash, StorePacking};

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
enum BattleStatus {
    None: (),
    PlayerWon: (),
    OpponentWon: (),
    Draw: (),
}

#[derive(Copy, Drop, Serde)]
struct PlayerInfo {
    completed_level: u8,
    claim_day_count: u8,
    day_index: u32,
}

const POW_2_8: u128 = 256;
const POW_2_16: u128 = 65536;

impl PlayerInfoStorePacking of StorePacking<PlayerInfo, u128> {
    fn pack(value: PlayerInfo) -> u128 {
        value.completed_level.into() + (value.claim_day_count.into() * POW_2_8) + (value.day_index.into() * POW_2_16)
    }

    fn unpack(value: u128) -> PlayerInfo {
        PlayerInfo {
            completed_level: (value & 0xff).try_into().unwrap(),
            claim_day_count: ((value / POW_2_8) & 0xff).try_into().unwrap(),
            day_index: (value / POW_2_16).try_into().unwrap(),
        }
    }
}

#[starknet::interface]
trait IPlanCombat<TContractState> {
    fn fight(ref self: TContractState, player_moves: felt252, player_character: u8);
    fn claim_reward(ref self: TContractState);
    fn set_plans(ref self: TContractState, plans: Span<felt252>);
    fn set_levels_reward(ref self: TContractState, levels_reward: Span<u256>);
    fn set_claim_day_limit(ref self: TContractState, claim_day_limit: u8);
    fn get_levels_reward(self: @TContractState) -> Span<u256>;
    fn get_player_info(self: @TContractState, account: ContractAddress) -> PlayerInfo;
    fn get_claim_day_limit(self: @TContractState) -> u8;
    fn get_day_timestamp(self: @TContractState) -> (u64, u64);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::interface]
trait IAccessControl<TContractState> {
    fn has_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn get_role_admin(self: @TContractState, role: felt252) -> felt252;
    fn grant_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revoke_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounce_role(ref self: TContractState, role: felt252, account: ContractAddress);
}

#[starknet::contract]
mod plan_combat {

    use openzeppelin::upgrades::upgradeable::UpgradeableComponent::InternalTrait;
    use core::option::OptionTrait;
    use poseidon::poseidon_hash_span;
    use traits::TryInto;
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_block_info};
    use starknet::syscalls::replace_class_syscall;
    use plan_combat::imintable::{IMintableDispatcherTrait, IMintableDispatcher, IERC1155MintableDispatcherTrait, IERC1155MintableDispatcher};
    use plan_combat::math::{pow_2, safe_sub};
    use plan_combat::move;
    use super::{IAccessControl, IPlanCombat, PlayerInfo, BattleStatus};

    use openzeppelin::access::accesscontrol::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;
    const RoleAdmin: felt252 = 0xaffd781351ea8ad3cd67f64a8ffa5919206623ec343d2583ab317bb5bd2b82;
    const MaxCharacterId: u8 = 4;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        game_counter: u128,
        players: LegacyMap<ContractAddress, PlayerInfo>,
        mintable_token: IMintableDispatcher,
        mintable_erc1155: IERC1155MintableDispatcher,
        erc1155_id: u256,
        levels_reward: LegacyMap<u8, u256>, // based on 1
        levels_len: u8,
        plans: LegacyMap<u8, felt252>,
        plans_len: u8,
        default_stamina: u8,
        claim_day_limit: u8,

        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameResult: GameResult,
        ClaimReward: ClaimReward,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct GameResult {
        game_id: u128,
        player: ContractAddress,
        player_moves: felt252,
        player_character: u8,
        opponent_moves: felt252,
        opponent_character: u8,
        level: u8,
        status: BattleStatus,
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimReward {
        player: ContractAddress,
        reward: u256,
        level: u8,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, mintable_token: IMintableDispatcher, mintable_erc1155: IERC1155MintableDispatcher, erc1155_id: u256, claim_day_limit: u8) {
        self.initializer(owner, mintable_token, mintable_erc1155, erc1155_id, claim_day_limit);
    }

    #[external(v0)]
    impl PlanCombat of IPlanCombat<ContractState> {
        fn fight(ref self: ContractState, player_moves: felt252, player_character: u8) {
            assert(player_character>0 && player_character<=MaxCharacterId, 'invalid character id');
            let player = get_caller_address();
            let mut player_info = self._get_player_info(player);
            let levels_len = self.levels_len.read();
            assert(player_info.completed_level < levels_len, 'claim reward first');
            let plans_len = self.plans_len.read();
            assert(plans_len > 0, 'game paused');

            let game_id = self.game_counter.read() + 1;
            let salts1: Span<felt252> = array![player.into(), game_id.into(), player_info.completed_level.into(), 1].span();
            let moves_rand: u8 = (self._unsafe_random(salts1) % plans_len.into()).try_into().unwrap();
            let opponent_moves = self.plans.read(moves_rand);
            let salts2: Span<felt252> = array![player.into(), game_id.into(), player_info.completed_level.into(), 2].span();
            let opponent_character: u8 = (self._unsafe_random(salts2) % MaxCharacterId.into()).try_into().unwrap() + 1;
            let status = self._battle(player_moves, opponent_moves);
            let completed_level = player_info.completed_level + 1;
            if status == BattleStatus::PlayerWon {
                player_info.completed_level = completed_level;
            }else {
                player_info.completed_level = 0;
            }
            player_info.day_index = self._get_day_index(get_block_info().unbox().block_timestamp);
            
            self.emit(GameResult{game_id, player, player_moves, player_character, opponent_moves, opponent_character, level: completed_level, status});
            self.game_counter.write(game_id);
            self.players.write(player, player_info);
        }

        fn claim_reward(ref self: ContractState) {
            let player = get_caller_address();
            let mut player_info = self._get_player_info(player);
            assert(player_info.completed_level > 0, 'no reward left');
            let claim_day_limit = self.claim_day_limit.read();
            assert(player_info.claim_day_count < claim_day_limit, 'reached the daily claim limit');
            let mut mintable_token = self.mintable_token.read();
            let levels_len = self.levels_len.read();
            if player_info.completed_level > levels_len {
                player_info.completed_level = levels_len;
            }
            let reward = self.levels_reward.read(player_info.completed_level);
            mintable_token.mint(player, reward);
            self.emit(ClaimReward {player: player, reward: reward, level: player_info.completed_level});
            
            let nft_claimable = player_info.completed_level >= levels_len;
            player_info.completed_level = 0;
            player_info.claim_day_count += 1;
            self.players.write(player, player_info);
            if nft_claimable {
                let mintable_erc1155 = self.mintable_erc1155.read();
                let erc1155_id = self.erc1155_id.read();
                mintable_erc1155.mint(player, erc1155_id, 1);
            }
        }

        fn set_plans(ref self: ContractState, plans: Span<felt252>) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            self._set_plans(plans);
        }

        fn set_levels_reward(ref self: ContractState, levels_reward: Span<u256>) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            self._set_levels(levels_reward);
        }

        fn set_claim_day_limit(ref self: ContractState, claim_day_limit: u8) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            self.claim_day_limit.write(claim_day_limit);
        }

        fn get_levels_reward(self: @ContractState) -> Span<u256> {
            let mut items: Array<u256> = array![];
            let mut i: u8 = 1;
            let len = self.levels_len.read();
            loop {
                if i > len {
                    break items.span();
                }
                items.append(self.levels_reward.read(i));
                i += 1;
            }
        }

        fn get_player_info(self: @ContractState, account: ContractAddress) -> PlayerInfo {
            self._get_player_info(account)
        }

        fn get_claim_day_limit(self: @ContractState) -> u8 {
            self.claim_day_limit.read()
        }

        fn get_day_timestamp(self: @ContractState) -> (u64, u64) {
            self._get_day_timestamp()
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(RoleUpgrader);
            self.upgradeable._upgrade(class_hash);
        }
    }

    #[generate_trait]
    impl InteralImpl of InteralTrait {
        fn initializer(ref self: ContractState, owner: ContractAddress, mintable_token: IMintableDispatcher, mintable_box: IERC1155MintableDispatcher, erc1155_id: u256, claim_day_limit: u8) {
            self.accesscontrol._grant_role(RoleDefaultAdmin, owner);
            self.mintable_token.write(mintable_token);
            self.mintable_erc1155.write(mintable_box);
            self.erc1155_id.write(erc1155_id);
            self.claim_day_limit.write(claim_day_limit);
        }

        fn _unsafe_random(self: @ContractState, salts: Span<felt252>) -> u256 {
            let res: u256 = poseidon_hash_span(salts).into();
            res
        }

        fn _set_plans(ref self: ContractState, plans: Span<felt252>) {
            let len = plans.len();
            let mut i: usize = 0;
            loop {
                if i == len {
                    break;
                }
                let plan = *plans.at(i);
                self.plans.write(i.try_into().unwrap(), plan);
                i += 1;
            };
            self.plans_len.write(len.try_into().unwrap());
        }

        fn _set_levels(ref self: ContractState, levels_reward: Span<u256>) {
            let len = levels_reward.len();
            assert(len > 0, 'empty levels');
            let mut previous_reward: u256 = 0;
            let mut i: usize = 0;
            loop {
                if i == len {
                    break;
                }
                let reward = *levels_reward.at(i);
                assert(reward >= previous_reward, 'invalid reward value');
                i += 1;
                self.levels_reward.write(i.try_into().unwrap(), reward);
            };
            self.levels_len.write(len.try_into().unwrap());
        }

        fn _get_day_index(self: @ContractState, timestamp: u64) -> u32 {
            (timestamp / 86400).try_into().unwrap() + 1
        }

        fn _get_day_timestamp(self: @ContractState) -> (u64, u64) {
            let timestamp = get_block_info().unbox().block_timestamp;
            (timestamp, (timestamp/86400 + 1) * 86400)
        }

        fn _get_player_info(self: @ContractState, player: ContractAddress) -> PlayerInfo {
            let mut player_info = self.players.read(player);
            let timestamp = get_block_info().unbox().block_timestamp;
            let day_index = self._get_day_index(timestamp);
            if player_info.day_index != day_index {
                player_info.claim_day_count = 0;
            }
            player_info
        }

        fn _battle(self: @ContractState, player_moves: felt252, opponent_moves: felt252) -> BattleStatus {
            let mut i: u128 = 0;
            let player_moves_u256: u256 = player_moves.into();
            let opponent_moves_u256: u256 = opponent_moves.into();
            let mut player_stamina: u8 = 40;
            let mut player_hp: u8 = 100;
            let mut opponent_stamina: u8 = 40;
            let mut opponent_hp: u8 = 100;
            loop {
                if i == 10 {
                    break;
                }
                let factor = pow_2((i%16)*8_u128);
                let mut player_arg = player_moves_u256.low;
                if i>15 {
                    player_arg = player_moves_u256.high;
                }
                let mut player_move: u8 = ((player_arg / factor) & 0xff).try_into().unwrap();
                let (mut player_stamina_cost, mut player_priority, mut player_atk, mut player_def) = move::get_move_attrs(player_move);
                if player_stamina_cost > player_stamina {
                    player_move = 0;
                    player_stamina_cost = 0;
                    player_atk = 0;
                    player_def = 0;
                }

                let mut opponent_arg = opponent_moves_u256.low;
                if i>15 {
                    opponent_arg = opponent_moves_u256.high;
                }
                let mut opponent_move: u8 = ((opponent_arg / factor) & 0xff).try_into().unwrap();
                let (mut opponent_stamina_cost, mut opponent_priority, mut opponent_atk, mut opponent_def) = move::get_move_attrs(opponent_move);
                if opponent_stamina_cost > opponent_stamina {
                    opponent_move = 0;
                    opponent_stamina_cost = 0;
                    opponent_atk = 0;
                    opponent_def = 0;
                }

                if player_priority > opponent_priority && player_move != move::DefenceMove {
                    opponent_atk = 0;
                    opponent_def = 0;
                }else if player_priority < opponent_priority && opponent_move != move::DefenceMove {
                    player_atk = 0;
                    player_atk = 0;
                }
                let player_dmg = safe_sub(player_atk, opponent_def);
                let opponent_dmg = safe_sub(opponent_atk, player_def);

                player_hp = safe_sub(player_hp, opponent_dmg);
                opponent_hp = safe_sub(opponent_hp, player_dmg);
                if player_hp==0 || opponent_hp==0 {
                    break;
                }
                player_stamina -= player_stamina_cost;
                opponent_stamina -= opponent_stamina_cost;

                i += 1;
            };
            if player_hp > opponent_hp {
                return BattleStatus::PlayerWon;
            }else if player_hp == opponent_hp {
                return BattleStatus::Draw;
            }else {
                return BattleStatus::OpponentWon;
            }
        }
    }

}

