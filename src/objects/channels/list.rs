use std::sync::Arc;

use tokio::sync::RwLock;
use hashbrown::HashMap;

use colored::Colorize;
use peace_database::Database;

use crate::types::ChannelList;

use super::{base::ChannelBase, Channel};

pub struct ChannelListBuilder {}

impl ChannelListBuilder {
    /// Initial channels list from database
    pub async fn channels_from_database(database: &Database) -> ChannelList {
        info!(
            "{}",
            "Initializing default chat channels...".bold().bright_blue()
        );
        let mut channels: ChannelList = HashMap::new();
        // Get channels from database
        match database.pg.structs_from_database::<ChannelBase>(r#"SELECT "name", "title", "read_priv", "write_priv", "auto_join" FROM "bancho"."channels";"#, &[]).await {
            Some(channel_bases) => {
                for base in channel_bases.iter() {
                    channels.insert(base.name.clone(), Arc::new(RwLock::new(Channel::from_base(&base).await)));
                }
                info!("{}", format!("Channels successfully loaded: {:?};", channels.keys()).bold().green());
                channels
            },
            None => {
                error!("{}", format!("Failed to initialize chat channels").bold().red());
                panic!();
            }
        }
    }
}
