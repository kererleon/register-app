//! Dart's `Random(seed)` (dart-sdk/lib/_internal/vm/lib/math_patch.dart), so
//! that the emojis and stickers of the brainrot and israel backgrounds sit
//! in exactly the same places as in the Flutter app.

pub struct DartRandom {
    state: i64,
}

impl DartRandom {
    pub fn new(seed: i64) -> Self {
        let mut r = DartRandom { state: setup_seed(seed) };
        for _ in 0..4 {
            r.next_state();
        }
        r
    }

    fn next_state(&mut self) {
        const A: i64 = 0xffffda61;
        let lo = self.state & 0xFFFF_FFFF;
        let hi = ((self.state as u64) >> 32) as i64;
        self.state = A.wrapping_mul(lo).wrapping_add(hi);
    }

    pub fn next_int(&mut self, max: i64) -> i64 {
        const POW2_32: i64 = 1 << 32;
        if max & -max == max {
            self.next_state();
            return self.state & 0xFFFF_FFFF & (max - 1);
        }
        loop {
            self.next_state();
            let rnd32 = self.state & 0xFFFF_FFFF;
            let result = rnd32 % max;
            if rnd32 - result + max <= POW2_32 {
                return result;
            }
        }
    }

    pub fn next_double(&mut self) -> f64 {
        let a = self.next_int(1 << 26) as f64;
        let b = self.next_int(1 << 27) as f64;
        (a * (1u64 << 27) as f64 + b) / (1u64 << 53) as f64
    }
}

fn setup_seed(n: i64) -> i64 {
    let mut n = (!n).wrapping_add(n.wrapping_shl(21));
    n ^= ((n as u64) >> 24) as i64;
    n = n.wrapping_mul(265);
    n ^= ((n as u64) >> 14) as i64;
    n = n.wrapping_mul(21);
    n ^= ((n as u64) >> 28) as i64;
    n = n.wrapping_add(n.wrapping_shl(31));
    if n == 0 { 0x5a17 } else { n }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The same numbers as Dart's `Random(7)` and `Random(9)` (checked with
    /// the Dart SDK).
    #[test]
    fn same_as_dart() {
        for (seed, expected) in [
            (7, "0 0.519300071384 9 6 0.209844086201 11 1 0.452494925446 2 4 0.465500271656 8"),
            (9, "1 0.556807735672 11 0 0.409829272604 10 8 0.913375531088 3 3 0.324314699749 6"),
        ] {
            let mut r = DartRandom::new(seed);
            let mut out = Vec::new();
            for _ in 0..4 {
                out.push(r.next_int(10).to_string());
                out.push(format!("{:.12}", r.next_double()));
                out.push(r.next_int(12).to_string());
            }
            assert_eq!(out.join(" "), expected);
        }
    }
}

/// Dart's `String.hashCode` in the VM (Jenkins one-at-a-time over the
/// UTF-16 code units, 30 bits), the seed of the subject icon patterns.
pub fn string_hash(s: &str) -> i64 {
    let mut h: u32 = 0;
    for unit in s.encode_utf16() {
        h = h.wrapping_add(unit as u32);
        h = h.wrapping_add(h << 10);
        h ^= h >> 6;
    }
    h = h.wrapping_add(h << 3);
    h ^= h >> 11;
    h = h.wrapping_add(h << 15);
    h &= (1 << 30) - 1;
    if h == 0 { 1 } else { h as i64 }
}

#[cfg(test)]
mod hash_tests {
    /// Values from the Dart SDK.
    #[test]
    fn same_as_dart() {
        assert_eq!(super::string_hash("Informatik"), 173073818);
        assert_eq!(super::string_hash("Deutsch"), 38289626);
        assert_eq!(super::string_hash("Systeme und Netze"), 211888710);
        assert_eq!(super::string_hash("Technologie und Planung"), 762964737);
        assert_eq!(super::string_hash("Bewegung und Sport"), 767898156);
    }
}
