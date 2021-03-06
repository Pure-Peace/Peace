#[macro_use]
extern crate log;

pub mod beatmaps;
pub mod osu_api;
#[cfg(feature = "peace_api")]
pub mod peace_api;
#[cfg(feature = "pp_server_api")]
pub mod pp_server_api;
