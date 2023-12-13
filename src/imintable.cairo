use starknet::ContractAddress;

#[starknet::interface]
trait IMintable<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}

#[starknet::interface]
trait IERC1155Mintable<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, id: u256, value: u256);
}