use crate::core::text::{StringKey, Strings};

/// Row timestamp label (`B-6.4.8`).
pub struct RelativeTime;

impl RelativeTime {
    pub fn label(from: f64, now: f64, strings: &Strings) -> String {
        Self::label_with_offset(from, now, strings, 0)
    }

    pub fn label_with_offset(
        from: f64,
        now: f64,
        strings: &Strings,
        tz_offset_seconds: i32,
    ) -> String {
        let seconds = now - from;
        if seconds < 60.0 {
            return strings.get(StringKey::TimeNow).to_string();
        }
        if seconds < 3600.0 {
            let mins = (seconds / 60.0) as i64;
            return strings.format(StringKey::TimeMinutesAgo, &[("n", &mins.to_string())]);
        }
        if seconds < 86_400.0 {
            let hours = (seconds / 3600.0) as i64;
            return strings.format(StringKey::TimeHoursAgo, &[("n", &hours.to_string())]);
        }
        let local_secs = (from.floor() as i64) + (tz_offset_seconds as i64);
        let secs_of_day = local_secs.rem_euclid(86_400);
        let hour = secs_of_day / 3600;
        let minute = (secs_of_day % 3600) / 60;
        format!("{:02}:{:02}", hour, minute)
    }
}
