use std::cmp::Ordering;

use crate::document_format::BinaryValue;

/// Numeric query values retain their integer representation during comparisons.
#[derive(Clone, Copy)]
pub(crate) enum NativeNumber {
    Int(i64),
    Double(f64),
}

impl NativeNumber {
    pub(crate) fn from_binary(value: &BinaryValue) -> Option<Self> {
        match value {
            BinaryValue::Int(value)
            | BinaryValue::DateTimeMicros(value)
            | BinaryValue::DurationMicros(value) => Some(Self::Int(*value)),
            BinaryValue::Double(value) => Some(Self::Double(*value)),
            _ => None,
        }
    }

    pub(crate) fn partial_cmp(self, other: Self) -> Option<Ordering> {
        match (self, other) {
            (Self::Int(left), Self::Int(right)) => Some(left.cmp(&right)),
            (Self::Double(left), Self::Double(right)) => left.partial_cmp(&right),
            (Self::Int(left), Self::Double(right)) => compare_integer_double(left, right),
            (Self::Double(left), Self::Int(right)) => {
                compare_integer_double(right, left).map(Ordering::reverse)
            }
        }
    }

    pub(crate) fn total_cmp(self, other: Self) -> Ordering {
        match self.partial_cmp(other) {
            Some(ordering) if ordering != Ordering::Equal => ordering,
            // Preserve the existing float ordering for signed zero and NaN.
            // Only equal or unordered values reach this conversion.
            _ => self.as_double().total_cmp(&other.as_double()),
        }
    }

    fn as_double(self) -> f64 {
        match self {
            Self::Int(value) => value as f64,
            Self::Double(value) => value,
        }
    }
}

fn compare_integer_double(integer: i64, double: f64) -> Option<Ordering> {
    if double.is_nan() {
        return None;
    }
    // i64::MAX rounds up to 2^63 as f64, so the upper bound is exclusive.
    if double >= 9_223_372_036_854_775_808.0 {
        return Some(Ordering::Less);
    }
    if double < -9_223_372_036_854_775_808.0 {
        return Some(Ordering::Greater);
    }
    // The cast is now in range. Compare the integer parts exactly, then the
    // remaining fraction without ever rounding the i64 to a float.
    Some(match integer.cmp(&(double as i64)) {
        Ordering::Equal if double.fract() > 0.0 => Ordering::Less,
        Ordering::Equal if double.fract() < 0.0 => Ordering::Greater,
        ordering => ordering,
    })
}
