use crate::{
    database::Database, objects::OsuApi, settings::bancho::BanchoConfig, types::ChannelList,
};
use crate::{objects::PlayerSessions, utils};

use actix_web::{
    dev::Server,
    web::{Data, Path},
};
use actix_web::{get, HttpResponse, Responder};
use async_std::{channel::Sender, sync::RwLock};
use maxminddb::Reader;
use memmap::Mmap;

use std::time::Instant;

/// GET "/test_pg"
#[get("/test_pg")]
pub async fn test_pg(database: Data<Database>) -> impl Responder {
    let start = Instant::now();
    let contents = database
        .pg
        .query_first_simple(r#"SELECT 'PurePeace' as "name";"#)
        .await;
    let end = start.elapsed();
    let name: String = contents.get("name");
    HttpResponse::Ok()
        .set_header("Content-Type", "text/html; charset=UTF-8")
        .body(format!("{}\n{:.2?}", name, end))
}

/// GET "/test_redis"
#[get("/test_redis")]
pub async fn test_redis(database: Data<Database>) -> impl Responder {
    let start = Instant::now();
    let _ = database.redis.set("test", &["PurePeace", "NX"]).await;
    let contents: String = database.redis.get("test").await.unwrap();
    let end = start.elapsed();
    HttpResponse::Ok()
        .set_header("Content-Type", "text/html; charset=UTF-8")
        .body(format!("{}\n{:.2?}", contents, end))
}

/// GET "/test_async_lock"
#[get("/test_async_lock")]
pub async fn test_async_lock(player_sessions: Data<RwLock<PlayerSessions>>) -> impl Responder {
    let start = Instant::now();
    let player_sessions = player_sessions.read().await;
    let _map = player_sessions.token_map.read().await;
    let end = start.elapsed();
    HttpResponse::Ok()
        .set_header("Content-Type", "text/html; charset=UTF-8")
        .body(&format!("{:.2?}", end))
}

/// GET "/test_player_read"
#[get("/test_player_read/{token}")]
pub async fn test_player_read(
    token: Path<String>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    let start = Instant::now();
    let player_info = match player_sessions.read().await.get_player_data(&token.0).await {
        Some(player_data) => format!("{:?}", player_data),
        None => "non this player".to_string(),
    };
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("{} {:.2?}", player_info, end))
}

/// GET "/test_player_money_add"
#[get("/test_player_money_add/{token}")]
pub async fn test_player_money_add(
    token: Path<String>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    let start = Instant::now();
    let player_sessions = player_sessions.read().await;
    let map = player_sessions.token_map.read().await;
    let player_info = match map.get(&token.0) {
        Some(player) => {
            // (*player).money += 1;
            //async_std::task::sleep(std::time::Duration::from_secs(1)).await;
            format!("{:?}", *player)
        }
        None => "non this player".to_string(),
    };
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("{} {:.2?}", player_info, end))
}

/// GET "/test_player_money_reduce"
#[get("/test_player_money_reduce/{token}")]
pub async fn test_player_money_reduce(
    token: Path<String>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    let start = Instant::now();
    let player_sessions = player_sessions.read().await;
    let map = player_sessions.token_map.read().await;
    let player_info = match map.get(&token.0) {
        Some(player) => {
            // (*player).money -= 1;
            format!("{:?}", *player)
        }
        None => "non this player".to_string(),
    };
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("{:?} {:.2?}", player_info, end))
}

/// GET "/test_player_money_reduce_special"
#[get("/test_player_money_reduce_special/{token}")]
pub async fn test_player_money_reduce_special(
    token: Path<String>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    let start = Instant::now();
    let player_info = player_sessions
        .read()
        .await
        .handle_player_get(&token.0, |_player| Some(()) /* (*player).money -= 1 */)
        .await;
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("{:?} {:.2?}", player_info, end))
}

/// GET "/player_sessions_all"
#[get("/player_sessions_all")]
pub async fn player_sessions_all(player_sessions: Data<RwLock<PlayerSessions>>) -> impl Responder {
    HttpResponse::Ok().body(player_sessions.read().await.map_to_string().await)
}

/// GET "/player_maps_info"
#[get("/player_maps_info")]
pub async fn player_maps_info(player_sessions: Data<RwLock<PlayerSessions>>) -> impl Responder {
    let start = Instant::now();
    let maps = player_sessions.read().await;
    let (token_map, id_session_map, name_session_map) = (
        maps.token_map.read().await,
        maps.id_session_map.read().await,
        maps.name_session_map.read().await,
    );
    HttpResponse::Ok().body(format!(
        "token_map: {}, id_session_map: {}, name_session_map: {}; time: {:.2?}",
        token_map.len(),
        id_session_map.len(),
        name_session_map.len(),
        start.elapsed()
    ))
}

/// GET "/player_channels_all"
#[get("/player_channels_all")]
pub async fn player_channels_all(channel_list: Data<RwLock<ChannelList>>) -> impl Responder {
    HttpResponse::Ok().body(format!("{:?}", channel_list.read().await.values()))
}

/// GET "/player_sessions_kick"
#[get("/player_sessions_kick/{token}")]
pub async fn player_sessions_kick(
    token: Path<String>,
    channel_list: Data<RwLock<ChannelList>>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    HttpResponse::Ok().body(
        match player_sessions
            .write()
            .await
            .logout(&token.0, Some(&channel_list))
            .await
        {
            Some(player) => format!("{}\n{:?}", token.0, player),
            None => "non this player".to_string(),
        },
    )
}

/// GET "/player_sessions_kick_uid"
#[get("/player_sessions_kick_uid/{user_id}")]
pub async fn player_sessions_kick_uid(
    user_id: Path<i32>,
    channel_list: Data<RwLock<ChannelList>>,
    player_sessions: Data<RwLock<PlayerSessions>>,
) -> impl Responder {
    HttpResponse::Ok().body(
        match player_sessions
            .write()
            .await
            .logout_with_id(user_id.0, Some(&channel_list))
            .await
        {
            Some(player) => format!("{:?}", player),
            None => "non this player".to_string(),
        },
    )
}

/// GET "/test_geo_ip"
#[get("/test_geo_ip/{ip_address}")]
pub async fn test_geo_ip(
    ip_address: Path<String>,
    geo_db: Data<Option<Reader<Mmap>>>,
) -> impl Responder {
    match utils::geo_ip_info(&ip_address.to_string(), &geo_db.get_ref()).await {
        Ok(json_success) => HttpResponse::Ok()
            .content_type("application/json; charset=utf-8")
            .body(json_success),
        Err(json_error) => HttpResponse::Ok()
            .content_type("application/json; charset=utf-8")
            .body(json_error),
    }
}

/// GET "/bancho_config_get"
#[get("/bancho_config_get")]
pub async fn bancho_config_get(bancho_config: Data<RwLock<BanchoConfig>>) -> impl Responder {
    HttpResponse::Ok().body(format!("{:?}", bancho_config.read().await))
}

/// GET "/bancho_config_update"
#[get("/bancho_config_update")]
pub async fn bancho_config_update(
    database: Data<Database>,
    bancho_config: Data<RwLock<BanchoConfig>>,
) -> impl Responder {
    let result = bancho_config.write().await.update(&database).await;
    HttpResponse::Ok().body(format!("{}", result))
}

/// GET "/osu_api_test"
#[get("/osu_api_test")]
pub async fn osu_api_test(osu_api: Data<RwLock<OsuApi>>) -> impl Responder {
    let results = osu_api.write().await.test_all().await;
    HttpResponse::Ok()
        .content_type("application/json")
        .body(results)
}

/// GET "/osu_api_all"
#[get("/osu_api_all")]
pub async fn osu_api_all(osu_api: Data<RwLock<OsuApi>>) -> impl Responder {
    HttpResponse::Ok().body(format!("{:?}", osu_api.read().await))
}

/// GET "/osu_api_reload"
#[get("/osu_api_reload")]
pub async fn osu_api_reload(osu_api: Data<RwLock<OsuApi>>) -> impl Responder {
    let start = Instant::now();
    osu_api.write().await.reload_clients().await;
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("done in: {:?}", end))
}

/// GET "/server_stop"
#[get("/server_stop")]
pub async fn server_stop(sender: Data<Sender<Option<Server>>>) -> impl Responder {
    let start = Instant::now();
    let _ = sender.send(None).await;
    let end = start.elapsed();
    HttpResponse::Ok().body(format!("done in: {:?}", end))
}
