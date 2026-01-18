pub const AtmosphereConfig = struct {
    pub const DAWN_START: f32 = 0.20;
    pub const DAWN_END: f32 = 0.30;
    pub const DUSK_START: f32 = 0.70;
    pub const DUSK_END: f32 = 0.80;

    // Transition midpoints (previously magic numbers 0.35 and 0.75)
    pub const DAY_TRANSITION: f32 = 0.35;
    pub const NIGHT_TRANSITION: f32 = 0.75;
};
