use super::depends::*;
use crate::{
    handlers::web::get,
    objects::{Bancho, Caches},
};

const BASE: &'static str = "Bancho /web [GET]";

pub async fn handler(
    req: HttpRequest,
    path: Path<String>,
    counter: Data<IntCounterVec>,
    database: Data<Database>,
    geo_db: Data<Option<Reader<Mmap>>>,
    caches: Data<Caches>,
    bancho: Data<Bancho>,
) -> HttpResponse {
    counter.with_label_values(&["/web", "get", "start"]).inc();
    // Get real request ip
    let request_ip = match peace_utils::web::get_realip(&req).await {
        Ok(ip) => ip,
        Err(_) => {
            return HttpResponse::BadRequest().body("bad requests");
        }
    };

    let ctx = || Context {
        req,
        counter: &counter,
        bancho: &bancho,
        database: &database,
        geo_db: &geo_db,
        caches: &caches,
    };

    debug!("{} Path: <{}>; ip: {}", BASE, path, request_ip);

    let handle_start = std::time::Instant::now();
    let handle_path = path.replace(".php", "");
    let resp = match handle_path.as_str() {
        "check-updates" => get::check_updates(&ctx()).await,
        /*"bancho_connect" => {}*/
        /* "maps/" => get::osu_get_beatmap_update(&ctx()).await, */
        "lastfm" => get::lastfm(&ctx()).await,
        "osu-rate" => get::osu_rate(&ctx()).await,
        "osu-addfavourite" => get::osu_add_favourite(&ctx()).await,
        /*"osu-markasread" => {}*/
        "osu-getreplay" => get::osu_get_replay(&ctx()).await,
        "osu-getfavourites" => get::osu_get_favourites(&ctx()).await,
        "osu-getfriends" => get::osu_get_friends(&ctx()).await,
        "osu-getseasonal" => get::osu_get_seasonal(&ctx()).await,
        /* "osu-get-beatmap-topic" => {}
        "osu-search" => {}
        "osu-search-set" => {}  */
        "osu-osz2-getscores" => get::osu_osz2_get_scores(&ctx()).await,
        //"osu-osz2-bmsubmit-getid" => {}
        _ => {
            warn!("{} Unimplemented path: <{}>", BASE, path);
            HttpResponse::Ok().body("ok")
        }
    };

    let handle_end = handle_start.elapsed();
    info!(
        "{} Path: <{}> done; time spent: {:?}",
        BASE, path, handle_end
    );

    resp
}
