const DefenceMove: u8 = 24;

fn get_move_attrs(move_id: u8) -> (u8,u8,u8,u8) {
    if move_id == 0{
        (0,0,0,0)
    }else if move_id == 1 {
        (3,52,15,0)
    }else if move_id == 2 {
        (2,71,10,0)
    }else if move_id == 3 {
        (2,61,12,0)
    }else if move_id == 4 {
        (3,55,15,0)
    }else if move_id == 5 {
        (8,87,32,0)
    }else if move_id == 6 {
        (4,60,18,0)
    }else if move_id == 7 {
        (4,62,15,0)
    }else if move_id == 8 {
        (5,78,18,0)
    }else if move_id == 9 {
        (8,85,38,0)
    }else if move_id == 10 {
        (2,48,18,0)
    }else if move_id == 11 {
        (5,76,21,0)
    }else if move_id == 12 {
        (5,80,16,0)
    }else if move_id == 13 {
        (4,53,20,0)
    }else if move_id == 14 {
        (8,86,34,0)
    }else if move_id == 15 {
        (4,68,13,0)
    }else if move_id == 16 {
        (3,46,20,10)
    }else if move_id == 17 {
        (3,74,12,0)
    }else if move_id == 18 {
        (4,54,18,12)
    }else if move_id == 19 {
        (7,84,30,0)
    }else if move_id == 20 {
        (2,32,46,0)
    }else if move_id == 21 {
        (3,44,53,0)
    }else if move_id == 22 {
        (3,42,51,0)
    }else if move_id == 23 {
        (9,90,40,0)
    }else if move_id == 24 {
        (1,100,0,41)
    }else {
        (0,0,0,0)
    }
}

#[cfg(test)]
mod move_tests {
    use debug::PrintTrait;

    #[test]
    #[available_gas(20000000)]
    fn test_get_move_attrs() {
        let (stamina, priority, atk, def) = super::get_move_attrs(22);
        assert(stamina==3 && priority==42 && atk==51 && def==0, 'get_move_attrs error');
    }

}