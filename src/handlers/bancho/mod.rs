mod common;
mod login;
pub mod packets;
pub mod parser;
pub mod sessions;
pub use common::*;

pub use login::login;

use ntex::web::types::Data;
use tokio::sync::RwLock;
use peace_database::Database;
use std::sync::Weak;

use crate::objects::{Bancho, Player, PlayerData};

pub struct HandlerContext<'a> {
    pub request_ip: &'a String,
    pub token: &'a String,
    pub id: i32,
    pub name: &'a String,
    pub u_name: &'a Option<String>,
    pub data: &'a PlayerData,
    pub weak_player: &'a Weak<RwLock<Player>>,
    pub bancho: &'a Data<Bancho>,
    pub database: &'a Data<Database>,
    pub payload: &'a [u8],
}
