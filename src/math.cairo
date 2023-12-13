use traits::TryInto;
use option::OptionTrait;

fn safe_sub<T, impl TPartialOrd: PartialOrd<T>, impl TSub: Sub<T>, impl TTryInto: TryInto<felt252, T>, impl DropT: Drop<T>, impl CopyT: Copy<T>>(
    a: T, b: T
) -> T {
    if a > b {
        return a - b;
    }
    0.try_into().unwrap()
}

fn pow_2(exponent: u128) -> u128 {
    assert(exponent%8==0 && exponent<128, 'not supported expoent');
    if exponent == 0 {
        1
    }else if exponent == 8 {
        256
    }else if exponent == 16 {
        65536
    }else if exponent == 24 {
        16777216
    }else if exponent == 32 {
        4294967296
    }else if exponent == 40 {
        1099511627776
    }else if exponent == 48 {
        281474976710656
    }else if exponent == 56 {
        72057594037927936
    }else if exponent == 64 {
        18446744073709551616
    }else if exponent == 72 {
        4722366482869645213696
    }else if exponent == 80 {
        1208925819614629174706176
    }else if exponent == 88 {
        309485009821345068724781056
    }else if exponent == 96 {
        79228162514264337593543950336
    }else if exponent == 104 {
        20282409603651670423947251286016
    }else if exponent == 112 {
        5192296858534827628530496329220096
    }else if exponent == 120 {
        1329227995784915872903807060280344576
    }else {
        0
    }
}

#[cfg(test)]
mod math_tests {

    use super::safe_sub;
    use super::pow_2;

    #[test]
    #[available_gas(20000000)]
    fn test_safe_sub() {
        assert(safe_sub(100_u8, 90_u8)==10_u8, '"100 - 90" should eq 10');
        assert(safe_sub(100_u8, 110_u8)==0_u8, '"100 - 110" should eq 0');
        assert(safe_sub(0_u8, 110_u8)==0_u8, '"0 - 110" should eq 0');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_pow_2() {
        assert(pow_2(0)==1, 'pow_2(0) should eq 1');
        assert(pow_2(56)==72057594037927936, 'pow_2(56) failed');
            
        assert((0x010203040506/pow_2(0)) & 0xff == 0x06, 'should be 0x06');
        assert((0x010203040506/pow_2(8)) & 0xff == 0x05, 'should be 0x05');
        assert((0x010203040506/pow_2(16)) & 0xff == 0x04, 'should be 0x04');
        assert((0x010203040506/pow_2(24)) & 0xff == 0x03, 'should be 0x03');
        assert((0x010203040506/pow_2(32)) & 0xff == 0x02, 'should be 0x02');
        assert((0x010203040506/pow_2(40)) & 0xff == 0x01, 'should be 0x01');
    }

}