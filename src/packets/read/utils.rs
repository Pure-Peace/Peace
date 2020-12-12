use std::convert::TryInto;
use std::str;

use actix_web::web::{Bytes, Data};
use async_std::sync::RwLock;

use num_traits::{FromPrimitive, ToPrimitive};

use crate::{
    constants::id,
    database::Database,
    objects::{Player, PlayerData, PlayerSessions},
    packets,
    types::ChannelList,
};

pub struct HandlerData<'a> {
    pub player_sessions: &'a Data<RwLock<PlayerSessions>>,
    pub database: &'a Data<Database>,
    pub channel_list: &'a Data<RwLock<ChannelList>>,
    pub token: &'a String,
    pub player_data: PlayerData,
}

#[derive(Debug)]
pub struct ClientPacket {}

impl ClientPacket {
    pub async fn handle<'a>(&self, handler_data: &HandlerData<'a>) {
        println!("{:?} {:?}", self, handler_data.player_data);
    }
}

pub struct PayloadReader<'a> {
    pub payload: &'a [u8],
    pub index: usize,
}

impl<'a> PayloadReader<'a> {
    pub fn new(payload: &'a [u8]) -> Self {
        PayloadReader { payload, index: 0 }
    }

    #[inline(always)]
    pub fn read_string(&mut self) -> &str {
        if self.payload[self.index] != 11 {
            return "";
        }
        self.index += 1;
        let data_length = self.read_uleb128() as usize;
        let data = &self.payload[self.index..self.index + data_length];

        str::from_utf8(data).unwrap_or("")
    }

    #[inline(always)]
    pub fn read_uleb128(&mut self) -> u32 {
        let (val, length) = read_uleb128(&self.payload[self.index..]);
        self.index += length;
        val
    }
}

pub struct PacketReader {
    pub buf: Vec<u8>,
    pub index: usize,
    pub current_packet: id,
    pub payload_length: usize,
    pub finish: bool,
    pub payload_count: u16,
    pub packet_count: u16,
}

impl PacketReader {
    #[inline(always)]
    pub fn from_bytes(body: Bytes) -> Self {
        PacketReader::from_vec(body.to_vec())
    }

    #[inline(always)]
    pub fn from_vec(body: Vec<u8>) -> Self {
        PacketReader {
            buf: body,
            index: 0,
            current_packet: id::OSU_UNKNOWN_PACKET,
            payload_length: 0,
            finish: false,
            payload_count: 0,
            packet_count: 0,
        }
    }

    #[inline(always)]
    // Reset the packet reader
    pub fn reset(&mut self) {
        self.finish = false;
        self.index = 0;
        self.current_packet = id::OSU_UNKNOWN_PACKET;
        self.payload_length = 0;
        self.payload_count = 0;
        self.packet_count = 0;
    }

    #[inline(always)]
    /// Read packet header: (type, length)
    pub fn next(&mut self) -> Option<(id, Option<&[u8]>)> {
        if (self.buf.len() - self.index) < 7 {
            self.finish = true;
            return None;
        }
        // Slice header data [u8; 7]
        let header = &self.buf[self.index..self.index + 7];
        self.index += 7;

        // Get packet id and length
        let packet_id = id::from_u8(header[0]).unwrap_or_else(|| {
            warn!("PacketReader: unknown packet id({})", header[0]);
            id::OSU_UNKNOWN_PACKET
        });
        let length = u32::from_le_bytes(header[3..=6].try_into().unwrap());

        self.packet_count += 1;
        self.current_packet = packet_id.clone();

        // Read the payload
        let payload = match length {
            0 => None,
            _ => {
                self.payload_count += 1;
                self.payload_length = length as usize;
                // Skip this payload at next call
                self.index += self.payload_length;
                Some(&self.buf[self.index - self.payload_length..self.index])
            }
        };

        // Convert packet id to enum and return
        Some((packet_id, payload))
    }

    #[inline(always)]
    /// Read packet header: (type, length)
    pub fn read_header(body: Vec<u8>) -> Option<(id, u32)> {
        if body.len() < 7 {
            return None;
        }
        let header = &body[..7];
        Some((
            id::from_u8(header[0]).unwrap_or(id::OSU_UNKNOWN_PACKET),
            u32::from_le_bytes(header[3..=6].try_into().unwrap()),
        ))
    }
}

#[inline(always)]
pub fn read_uleb128(slice: &[u8]) -> (u32, usize) {
    let (mut val, mut shift, mut index) = (0, 0, 0);
    loop {
        let byte = slice[index];
        index += 1;
        if (byte & 0x80) == 0 {
            val |= (byte as u32) << shift;
            return (val, index);
        }
        val |= ((byte & 0x7f) as u32) << shift;
        shift += 7;
    }
}
