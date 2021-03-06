use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
pub struct PlayerBase {
    /// Player's unique id
    pub id: i32,
    /// Player's unique name
    pub name: String,
    /// Player's unique unicode name
    pub u_name: Option<String>,
    /// Argon2 crypted password md5
    pub password: String,
    pub privileges: i32,
    pub country: String,
}
