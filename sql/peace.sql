SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;
CREATE SCHEMA bancho;
COMMENT ON SCHEMA bancho IS 'Bancho configs';
CREATE SCHEMA beatmaps;
CREATE SCHEMA game_scores;
COMMENT ON SCHEMA game_scores IS 'User''s game scores (including 4 mode, and vanilla, relax, autopilot tables)';
CREATE SCHEMA game_stats;
COMMENT ON SCHEMA game_stats IS 'User''s game stats (such as PP, ACC, PC, TTH, etc.). including std, catch, taiko, mania and vn, ap, rx.';
CREATE SCHEMA "user";
COMMENT ON SCHEMA "user" IS 'user''s info and base data';
CREATE SCHEMA user_records;
COMMENT ON SCHEMA user_records IS 'user''s records, such as login, rename, etc.';
CREATE TYPE beatmaps.server AS ENUM (
    'ppy',
    'peace'
);
CREATE FUNCTION bancho.bancho_config_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	NEW.update_time = CURRENT_TIMESTAMP;
	IF NEW.enabled = TRUE THEN
		UPDATE "bancho"."config" SET "enabled" = FALSE WHERE "name" <> NEW."name" AND "enabled" = TRUE;
	END IF;
	RETURN NEW;
END$$;
CREATE FUNCTION beatmaps.beatmaps_map_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		NEW.update_time = CURRENT_TIMESTAMP;
		--only for insert
		IF (TG_OP = 'INSERT') THEN
			--if beatmap already exists and new has modifyed, we should delete old.
			perform FROM "beatmaps"."maps" WHERE "id" = NEW."id" AND "md5" <> NEW."md5";
			IF FOUND THEN
				DELETE FROM "beatmaps"."maps" WHERE "id" = NEW."id";
			END IF;
			--fixed rank status
			IF (NEW.fixed_rank_status IS NULL) THEN
				IF (NEW.rank_status = 2 OR NEW.rank_status = 1) THEN
					NEW.fixed_rank_status = TRUE;
				ELSE
					NEW.fixed_rank_status = FALSE;
				END IF;
			END IF;
		END IF;
	RETURN NEW;
END$$;
CREATE FUNCTION beatmaps.beatmaps_map_trigger_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		--only for insert
		IF (TG_OP = 'INSERT') THEN
			INSERT INTO beatmaps.stats ("id", "md5") VALUES (NEW."id", NEW."md5");
		END IF;
	RETURN NEW;
END$$;
CREATE FUNCTION game_scores.scores_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	NEW.update_time = CURRENT_TIMESTAMP;
	RETURN NEW;
END$$;
CREATE FUNCTION public.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	NEW.update_time = CURRENT_TIMESTAMP;
	RETURN NEW;
END$$;
CREATE FUNCTION "user".decrease_friend_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "friends_count" = "friends_count" - 1 WHERE "id" = OLD.user_id;
	RETURN OLD;
END$$;
CREATE FUNCTION "user".decrease_note_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "notes_count" = "notes_count" - 1 WHERE "id" = OLD.user_id;
	RETURN OLD;
END$$;
CREATE FUNCTION "user".increase_friend_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "friends_count" = "friends_count" + 1 WHERE "id" = NEW.user_id;
	RETURN NEW;
END$$;
CREATE FUNCTION "user".increase_note_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "notes_count" = "notes_count" + 1 WHERE "id" = NEW.user_id;
	RETURN NEW;
END$$;
CREATE FUNCTION "user".insert_related_on_base_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	INSERT INTO "user"."statistic" ("id") VALUES (NEW.id);
	
	INSERT INTO "user"."status" ("id") VALUES (NEW.id);
	
	INSERT INTO "user"."settings" ("id") VALUES (NEW.id);
	INSERT INTO "game_stats"."std" ("id") VALUES (NEW.id);
	INSERT INTO "game_stats"."catch" ("id") VALUES (NEW.id);
	INSERT INTO "game_stats"."taiko" ("id") VALUES (NEW.id);
	INSERT INTO "game_stats"."mania" ("id") VALUES (NEW.id);
	RETURN NEW;
END$$;
CREATE FUNCTION "user".safe_user_info() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		NEW.name = REPLACE(BTRIM(NEW.name), '_', ' ');
		NEW.email = LOWER(NEW.email);
		NEW.country = UPPER(NEW.country);
		NEW.name_safe = REPLACE(LOWER(NEW.name), ' ', '_');
		perform FROM "user"."base" WHERE u_name_safe = NEW.name_safe AND "id" <> NEW."id";
		IF FOUND THEN
			RAISE EXCEPTION 'name conflicts with an existing u_name';
		END IF;
		
		IF NEW.u_name IS NOT NULL THEN
			NEW.u_name = REPLACE(BTRIM(NEW.u_name), '_', ' ');
			NEW.u_name_safe = REPLACE(LOWER(NEW.u_name), ' ', '_');
			perform FROM "user"."base" WHERE name_safe = NEW.u_name_safe AND "id" <> NEW."id";
			IF FOUND THEN
				RAISE EXCEPTION 'u_name conflicts with an existing username';
			END IF;
		END IF;
		
		
		--only for user base info update
		IF (TG_OP = 'UPDATE') THEN
			--if renamed, insert into rename_records
			IF OLD.name <> NEW.name THEN
				INSERT INTO "user_records"."rename" ("user_id", "new_name", "old_name") VALUES (NEW.id, NEW.name, OLD.name);
			ELSIF (NEW.u_name IS NOT NULL) AND (OLD.u_name <> NEW.u_name) THEN
				INSERT INTO "user_records"."rename" ("user_id", "new_name", "old_name") VALUES (NEW.id, NEW.u_name, OLD.u_name);
			END IF;
		END IF;
	RETURN NEW;
END$$;
CREATE FUNCTION user_records.auto_online_duration() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	IF (NEW.create_time IS NOT NULL) AND (NEW.logout_time IS NOT NULL) THEN
		NEW.online_duration = NEW.logout_time - NEW.create_time;
		UPDATE "user"."statistic" SET "online_duration" = "online_duration" + NEW.online_duration WHERE "id" = NEW.user_id;
	END IF;
	RETURN NEW;
END$$;
CREATE FUNCTION user_records.increase_login_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "login_count" = "login_count" + 1 WHERE "id" = NEW.user_id;
		UPDATE "user"."address" SET used_times = used_times + 1 WHERE "id" = NEW."id";
	RETURN NEW;
END$$;
CREATE FUNCTION user_records.increase_rename_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
		UPDATE "user"."statistic" SET "rename_count" = "rename_count" + 1 WHERE "id" = NEW.user_id;
	RETURN NEW;
END$$;
SET default_tablespace = '';
SET default_table_access_method = heap;
CREATE TABLE bancho.channels (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    title character varying(255) NOT NULL,
    read_priv integer DEFAULT 1 NOT NULL,
    write_priv integer DEFAULT 2 NOT NULL,
    auto_join boolean DEFAULT false NOT NULL,
    create_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN bancho.channels.id IS 'unique channel id';
COMMENT ON COLUMN bancho.channels.name IS 'channel name';
COMMENT ON COLUMN bancho.channels.title IS 'channel title (topic)';
COMMENT ON COLUMN bancho.channels.read_priv IS 'privileges';
COMMENT ON COLUMN bancho.channels.write_priv IS 'privileges';
COMMENT ON COLUMN bancho.channels.auto_join IS 'auto join channel when login';
COMMENT ON COLUMN bancho.channels.create_time IS 'create time';
COMMENT ON COLUMN bancho.channels.update_time IS 'update time';
CREATE SEQUENCE bancho.channels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE bancho.channels_id_seq OWNED BY bancho.channels.id;
CREATE TABLE bancho.config (
    name character varying(255) NOT NULL,
    comment character varying(255),
    enabled boolean,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    settings jsonb
);
COMMENT ON COLUMN bancho.config.name IS 'unique config name';
COMMENT ON COLUMN bancho.config.comment IS 'comment';
COMMENT ON COLUMN bancho.config.enabled IS 'enabled status';
COMMENT ON COLUMN bancho.config.update_time IS 'auto update timestamp';
CREATE SEQUENCE beatmaps.peace_bid
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;
CREATE TABLE beatmaps.maps (
    id integer DEFAULT nextval('beatmaps.peace_bid'::regclass) NOT NULL,
    set_id integer DEFAULT nextval('beatmaps.peace_bid'::regclass) NOT NULL,
    md5 character varying(32) NOT NULL,
    fixed_rank_status boolean,
    title character varying(255) NOT NULL,
    title_unicode character varying(255),
    artist character varying(128) NOT NULL,
    artist_unicode character varying(128),
    diff_name character varying(128) NOT NULL,
    mapper character varying(32) NOT NULL,
    mapper_id integer NOT NULL,
    rank_status integer DEFAULT 0 NOT NULL,
    mode smallint NOT NULL,
    aim real,
    spd real,
    stars real DEFAULT 0.0 NOT NULL,
    bpm real DEFAULT 0.0 NOT NULL,
    cs real DEFAULT 0.0 NOT NULL,
    od real DEFAULT 0.0 NOT NULL,
    ar real DEFAULT 0.0 NOT NULL,
    hp real DEFAULT 0.0 NOT NULL,
    length integer DEFAULT 0 NOT NULL,
    length_drain integer DEFAULT 0 NOT NULL,
    source character varying(128),
    tags text,
    genre_id smallint DEFAULT 0,
    language_id smallint DEFAULT 0,
    storyboard boolean DEFAULT false,
    video boolean DEFAULT false,
    object_count integer DEFAULT 0 NOT NULL,
    slider_count integer DEFAULT 0 NOT NULL,
    spinner_count integer DEFAULT 0 NOT NULL,
    max_combo integer,
    stars_taiko real,
    stars_catch real,
    stars_mania real,
    ranked_by character varying(128),
    last_update timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    submit_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    approved_time timestamp(6) with time zone
);
COMMENT ON COLUMN beatmaps.maps.id IS 'beatmap id';
COMMENT ON COLUMN beatmaps.maps.set_id IS 'beatmapset id';
COMMENT ON COLUMN beatmaps.maps.fixed_rank_status IS 'is the beatmap rank status fixed';
COMMENT ON COLUMN beatmaps.maps.ranked_by IS 'beatmap ranked by';
COMMENT ON COLUMN beatmaps.maps.last_update IS 'beatmap last update';
COMMENT ON COLUMN beatmaps.maps.update_time IS 'system auto update time';
CREATE TABLE beatmaps.ratings (
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    rating smallint NOT NULL,
    comments character varying(255),
    update_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE beatmaps.stats (
    id integer NOT NULL,
    md5 character varying(32) NOT NULL,
    playcount integer DEFAULT 0 NOT NULL,
    play_time bigint DEFAULT 0 NOT NULL,
    pass integer DEFAULT 0 NOT NULL,
    fail integer DEFAULT 0 NOT NULL,
    clicked integer DEFAULT 0 NOT NULL,
    miss integer DEFAULT 0 NOT NULL,
    pick integer DEFAULT 0 NOT NULL,
    quit integer DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE TABLE game_scores.catch (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.catch.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.catch.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.catch.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.catch.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.catch.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.catch.mods IS 'play mods';
COMMENT ON COLUMN game_scores.catch.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.catch.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.catch.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.catch.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.catch.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.catch.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.catch.update_time IS 'last update time';
CREATE SEQUENCE game_scores.catch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.catch_id_seq OWNED BY game_scores.catch.id;
CREATE TABLE game_scores.catch_rx (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.catch_rx.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.catch_rx.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.catch_rx.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.catch_rx.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.catch_rx.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.catch_rx.mods IS 'play mods';
COMMENT ON COLUMN game_scores.catch_rx.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.catch_rx.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.catch_rx.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.catch_rx.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.catch_rx.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.catch_rx.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.catch_rx.update_time IS 'last update time';
CREATE SEQUENCE game_scores.catch_rx_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.catch_rx_id_seq OWNED BY game_scores.catch_rx.id;
CREATE TABLE game_scores.mania (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.mania.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.mania.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.mania.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.mania.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.mania.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.mania.mods IS 'play mods';
COMMENT ON COLUMN game_scores.mania.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.mania.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.mania.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.mania.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.mania.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.mania.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.mania.update_time IS 'last update time';
CREATE SEQUENCE game_scores.mania_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.mania_id_seq OWNED BY game_scores.mania.id;
CREATE TABLE game_scores.std (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.std.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.std.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.std.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.std.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.std.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.std.mods IS 'play mods';
COMMENT ON COLUMN game_scores.std.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.std.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.std.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.std.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.std.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.std.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.std.update_time IS 'last update time';
CREATE TABLE game_scores.std_ap (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.std_ap.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.std_ap.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.std_ap.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.std_ap.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.std_ap.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.std_ap.mods IS 'play mods';
COMMENT ON COLUMN game_scores.std_ap.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.std_ap.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.std_ap.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.std_ap.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.std_ap.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.std_ap.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.std_ap.update_time IS 'last update time';
CREATE SEQUENCE game_scores.std_ap_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.std_ap_id_seq OWNED BY game_scores.std_ap.id;
CREATE SEQUENCE game_scores.std_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.std_id_seq OWNED BY game_scores.std.id;
CREATE TABLE game_scores.std_rx (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.std_rx.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.std_rx.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.std_rx.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.std_rx.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.std_rx.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.std_rx.mods IS 'play mods';
COMMENT ON COLUMN game_scores.std_rx.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.std_rx.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.std_rx.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.std_rx.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.std_rx.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.std_rx.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.std_rx.update_time IS 'last update time';
CREATE SEQUENCE game_scores.std_rx_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.std_rx_id_seq OWNED BY game_scores.std_rx.id;
CREATE TABLE game_scores.std_scv2 (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.std_scv2.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.std_scv2.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.std_scv2.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.std_scv2.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.std_scv2.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.std_scv2.mods IS 'play mods';
COMMENT ON COLUMN game_scores.std_scv2.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.std_scv2.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.std_scv2.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.std_scv2.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.std_scv2.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.std_scv2.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.std_scv2.update_time IS 'last update time';
CREATE SEQUENCE game_scores.std_scv2_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.std_scv2_id_seq OWNED BY game_scores.std_scv2.id;
CREATE TABLE game_scores.taiko (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.taiko.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.taiko.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.taiko.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.taiko.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.taiko.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.taiko.mods IS 'play mods';
COMMENT ON COLUMN game_scores.taiko.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.taiko.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.taiko.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.taiko.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.taiko.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.taiko.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.taiko.update_time IS 'last update time';
CREATE SEQUENCE game_scores.taiko_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.taiko_id_seq OWNED BY game_scores.taiko.id;
CREATE TABLE game_scores.taiko_rx (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    map_md5 character varying(32) NOT NULL,
    score integer NOT NULL,
    pp_v1 real,
    pp_v2 real,
    pp_v2_raw jsonb,
    pp_v3 real,
    stars real,
    accuracy real NOT NULL,
    combo integer NOT NULL,
    mods integer NOT NULL,
    n300 integer NOT NULL,
    n100 integer NOT NULL,
    n50 integer NOT NULL,
    miss integer NOT NULL,
    geki integer NOT NULL,
    katu integer NOT NULL,
    playtime integer NOT NULL,
    perfect boolean DEFAULT false NOT NULL,
    status smallint DEFAULT 0 NOT NULL,
    grade character varying(4) DEFAULT 'N'::character varying NOT NULL,
    client_flags integer DEFAULT 0 NOT NULL,
    client_version integer NOT NULL,
    confidence smallint DEFAULT 100 NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    checked boolean DEFAULT false NOT NULL,
    validation boolean DEFAULT true NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    md5 character varying(32) NOT NULL,
    rep_md5 character varying(32),
    check_time timestamp(6) with time zone,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN game_scores.taiko_rx.id IS 'score''s unique id';
COMMENT ON COLUMN game_scores.taiko_rx.user_id IS 'user''s unique id';
COMMENT ON COLUMN game_scores.taiko_rx.map_md5 IS 'beatmap''s md5';
COMMENT ON COLUMN game_scores.taiko_rx.pp_v1 IS 'ppv1';
COMMENT ON COLUMN game_scores.taiko_rx.pp_v2 IS 'ppv2';
COMMENT ON COLUMN game_scores.taiko_rx.mods IS 'play mods';
COMMENT ON COLUMN game_scores.taiko_rx.playtime IS 'play time (seconds)';
COMMENT ON COLUMN game_scores.taiko_rx.perfect IS 'this score is full combo or not';
COMMENT ON COLUMN game_scores.taiko_rx.client_version IS 'the client version used to submit this score';
COMMENT ON COLUMN game_scores.taiko_rx.confidence IS 'credibility of score';
COMMENT ON COLUMN game_scores.taiko_rx.check_time IS 'last check time';
COMMENT ON COLUMN game_scores.taiko_rx.create_time IS 'submission time';
COMMENT ON COLUMN game_scores.taiko_rx.update_time IS 'last update time';
CREATE SEQUENCE game_scores.taiko_rx_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE game_scores.taiko_rx_id_seq OWNED BY game_scores.taiko_rx.id;
CREATE TABLE game_stats.catch (
    id integer NOT NULL,
    total_score bigint DEFAULT 0 NOT NULL,
    ranked_score bigint DEFAULT 0 NOT NULL,
    total_score_rx bigint DEFAULT 0 NOT NULL,
    ranked_score_rx bigint DEFAULT 0 NOT NULL,
    pp_v1 real DEFAULT 0.0 NOT NULL,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v1_rx real DEFAULT 0.0 NOT NULL,
    pp_v2_rx real DEFAULT 0.0 NOT NULL,
    playcount integer DEFAULT 0 NOT NULL,
    playcount_rx integer DEFAULT 0 NOT NULL,
    total_hits integer DEFAULT 0 NOT NULL,
    total_hits_rx integer DEFAULT 0 NOT NULL,
    accuracy real DEFAULT 0.0 NOT NULL,
    accuracy_rx real DEFAULT 0.0 NOT NULL,
    max_combo integer DEFAULT 0 NOT NULL,
    max_combo_rx integer DEFAULT 0 NOT NULL,
    playtime bigint DEFAULT 0 NOT NULL,
    playtime_rx bigint DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE game_stats.catch IS 'Catch the beat (including vanilla, relax)';
COMMENT ON COLUMN game_stats.catch.id IS 'user''s unique id';
CREATE TABLE game_stats.mania (
    id integer NOT NULL,
    total_score bigint DEFAULT 0 NOT NULL,
    ranked_score bigint DEFAULT 0 NOT NULL,
    pp_v1 real DEFAULT 0.0 NOT NULL,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    playcount integer DEFAULT 0 NOT NULL,
    total_hits integer DEFAULT 0 NOT NULL,
    accuracy real DEFAULT 0.0 NOT NULL,
    max_combo integer DEFAULT 0 NOT NULL,
    playtime bigint DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE game_stats.mania IS 'Mania (only vanilla)';
COMMENT ON COLUMN game_stats.mania.id IS 'user''s unique id';
CREATE TABLE game_stats.std (
    id integer NOT NULL,
    total_score bigint DEFAULT 0 NOT NULL,
    ranked_score bigint DEFAULT 0 NOT NULL,
    total_score_rx bigint DEFAULT 0 NOT NULL,
    ranked_score_rx bigint DEFAULT 0 NOT NULL,
    total_score_ap bigint DEFAULT 0 NOT NULL,
    ranked_score_ap bigint DEFAULT 0 NOT NULL,
    total_score_scv2 bigint DEFAULT 0 NOT NULL,
    ranked_score_scv2 bigint DEFAULT 0 NOT NULL,
    pp_v1 real DEFAULT 0.0 NOT NULL,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v1_rx real DEFAULT 0.0 NOT NULL,
    pp_v2_rx real DEFAULT 0.0 NOT NULL,
    pp_v1_ap real DEFAULT 0.0 NOT NULL,
    pp_v2_ap real DEFAULT 0.0 NOT NULL,
    pp_v2_scv2 real DEFAULT 0.0 NOT NULL,
    playcount integer DEFAULT 0 NOT NULL,
    playcount_rx integer DEFAULT 0 NOT NULL,
    playcount_ap integer DEFAULT 0 NOT NULL,
    playcount_scv2 integer DEFAULT 0 NOT NULL,
    total_hits integer DEFAULT 0 NOT NULL,
    total_hits_rx integer DEFAULT 0 NOT NULL,
    total_hits_ap integer DEFAULT 0 NOT NULL,
    total_hits_scv2 integer DEFAULT 0 NOT NULL,
    accuracy real DEFAULT 0.0 NOT NULL,
    accuracy_rx real DEFAULT 0.0 NOT NULL,
    accuracy_ap real DEFAULT 0.0 NOT NULL,
    accuracy_scv2 real DEFAULT 0.0 NOT NULL,
    max_combo integer DEFAULT 0 NOT NULL,
    max_combo_rx integer DEFAULT 0 NOT NULL,
    max_combo_ap integer DEFAULT 0 NOT NULL,
    max_combo_scv2 integer DEFAULT 0 NOT NULL,
    playtime bigint DEFAULT 0 NOT NULL,
    playtime_rx bigint DEFAULT 0 NOT NULL,
    playtime_ap bigint DEFAULT 0 NOT NULL,
    playtime_scv2 bigint DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE game_stats.std IS 'Standard (including vanilla, relax, autopilot, score v2)';
COMMENT ON COLUMN game_stats.std.id IS 'user''s unique id';
CREATE TABLE game_stats.taiko (
    id integer NOT NULL,
    total_score bigint DEFAULT 0 NOT NULL,
    ranked_score bigint DEFAULT 0 NOT NULL,
    total_score_rx bigint DEFAULT 0 NOT NULL,
    ranked_score_rx bigint DEFAULT 0 NOT NULL,
    pp_v1 real DEFAULT 0.0 NOT NULL,
    pp_v2 real DEFAULT 0.0 NOT NULL,
    pp_v1_rx real DEFAULT 0.0 NOT NULL,
    pp_v2_rx real DEFAULT 0.0 NOT NULL,
    playcount integer DEFAULT 0 NOT NULL,
    playcount_rx integer DEFAULT 0 NOT NULL,
    total_hits integer DEFAULT 0 NOT NULL,
    total_hits_rx integer DEFAULT 0 NOT NULL,
    accuracy real DEFAULT 0.0 NOT NULL,
    accuracy_rx real DEFAULT 0.0 NOT NULL,
    max_combo integer DEFAULT 0 NOT NULL,
    max_combo_rx integer DEFAULT 0 NOT NULL,
    playtime bigint DEFAULT 0 NOT NULL,
    playtime_rx bigint DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE game_stats.taiko IS 'Taiko (including vanilla, relax)';
COMMENT ON COLUMN game_stats.taiko.id IS 'user''s unique id';
CREATE TABLE public.db_versions (
    version character varying(15) DEFAULT '0.1.0'::character varying NOT NULL,
    author character varying(64) DEFAULT 'PurePeace'::character varying NOT NULL,
    sql text,
    release_note text,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN public.db_versions.version IS 'peace database version';
COMMENT ON COLUMN public.db_versions.author IS 'version publisher';
COMMENT ON COLUMN public.db_versions.sql IS 'database initial sql';
COMMENT ON COLUMN public.db_versions.release_note IS 'version release note';
CREATE TABLE public.versions (
    version character varying(15) DEFAULT '0.1.0'::character varying NOT NULL,
    author character varying(64) DEFAULT 'PurePeace'::character varying NOT NULL,
    db_version character varying(15) DEFAULT '0.1.0'::character varying NOT NULL,
    release_note text,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN public.versions.version IS 'peace version';
COMMENT ON COLUMN public.versions.author IS 'version publisher';
COMMENT ON COLUMN public.versions.db_version IS 'peace ''s database version';
COMMENT ON COLUMN public.versions.release_note IS 'version release note';
CREATE TABLE "user".address (
    id integer NOT NULL,
    user_id integer NOT NULL,
    time_offset integer NOT NULL,
    path character varying(255) NOT NULL,
    adapters text NOT NULL,
    adapters_hash character varying(255) NOT NULL,
    uninstall_id character varying(255) NOT NULL,
    disk_id character varying(255) NOT NULL,
    used_times bigint DEFAULT 0 NOT NULL,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".address IS 'User''s login hardware address';
COMMENT ON COLUMN "user".address.id IS 'address id, unique';
COMMENT ON COLUMN "user".address.user_id IS 'user_id, int 32';
COMMENT ON COLUMN "user".address.time_offset IS 'time_offset';
COMMENT ON COLUMN "user".address.path IS 'osu_path hash';
COMMENT ON COLUMN "user".address.adapters IS 'network physical addresses delimited by ''.''';
COMMENT ON COLUMN "user".address.adapters_hash IS 'adapters_hash';
COMMENT ON COLUMN "user".address.uninstall_id IS 'uniqueid1';
COMMENT ON COLUMN "user".address.disk_id IS 'uniqueid2';
COMMENT ON COLUMN "user".address.create_time IS 'create_time';
CREATE SEQUENCE "user".address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "user".address_id_seq OWNED BY "user".address.id;
CREATE TABLE "user".base (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    name_safe character varying(64) NOT NULL,
    u_name character varying(64),
    u_name_safe character varying(64),
    password character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    privileges integer DEFAULT 1 NOT NULL,
    country character varying(16) DEFAULT 'UN'::character varying NOT NULL,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".base IS 'Basic user information, such as user name, password, email, etc.';
COMMENT ON COLUMN "user".base.id IS 'user_id, int 32, unique';
COMMENT ON COLUMN "user".base.name IS 'username (unsafe), string, unique';
COMMENT ON COLUMN "user".base.name_safe IS 'username (safe), string, unique';
COMMENT ON COLUMN "user".base.u_name IS 'unicode username (unsafe), string, unique';
COMMENT ON COLUMN "user".base.u_name_safe IS 'unicode username (safe), string, unique';
COMMENT ON COLUMN "user".base.password IS 'user’s Argon2 crypted password hash';
COMMENT ON COLUMN "user".base.email IS 'email, string, unique';
COMMENT ON COLUMN "user".base.privileges IS 'user privileges';
COMMENT ON COLUMN "user".base.country IS 'user country';
COMMENT ON COLUMN "user".base.create_time IS 'user create time, auto create';
COMMENT ON COLUMN "user".base.update_time IS 'user info last update time, auto create and update';
CREATE SEQUENCE "user".base_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;
ALTER SEQUENCE "user".base_id_seq OWNED BY "user".base.id;
CREATE TABLE "user".beatmap_collections (
    user_id integer NOT NULL,
    beatmap_set_id integer NOT NULL,
    remark character varying(255),
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".beatmap_collections IS 'user''s online beatmap collections';
COMMENT ON COLUMN "user".beatmap_collections.user_id IS 'user_id, int 32';
COMMENT ON COLUMN "user".beatmap_collections.beatmap_set_id IS 'beatmap_set_id, int 32';
COMMENT ON COLUMN "user".beatmap_collections.remark IS 'why you like this map?';
COMMENT ON COLUMN "user".beatmap_collections.create_time IS 'create timestamp, auto';
CREATE TABLE "user".friends (
    user_id integer NOT NULL,
    friend_id integer NOT NULL,
    remark character varying(64),
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".friends IS 'User’s friends';
COMMENT ON COLUMN "user".friends.user_id IS 'user_id, int 32';
COMMENT ON COLUMN "user".friends.friend_id IS 'user_id, int 32';
COMMENT ON COLUMN "user".friends.remark IS 'friend remark, such as aka';
COMMENT ON COLUMN "user".friends.create_time IS 'create timestamp, auto';
CREATE TABLE "user".notes (
    id integer NOT NULL,
    user_id integer NOT NULL,
    content text NOT NULL,
    data text,
    type character varying(64) DEFAULT 0 NOT NULL,
    added_by character varying(32),
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".notes IS 'User’s notes, which may be rewards or warnings etc.';
COMMENT ON COLUMN "user".notes.id IS 'note id, unique';
COMMENT ON COLUMN "user".notes.user_id IS 'user_id, int 32';
COMMENT ON COLUMN "user".notes.content IS 'note, string';
COMMENT ON COLUMN "user".notes.type IS 'note type';
COMMENT ON COLUMN "user".notes.added_by IS 'added by who';
COMMENT ON COLUMN "user".notes.create_time IS 'note create time, auto create';
COMMENT ON COLUMN "user".notes.update_time IS 'note last update time, auto create and update';
CREATE SEQUENCE "user".notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;
ALTER SEQUENCE "user".notes_id_seq OWNED BY "user".notes.id;
CREATE TABLE "user".settings (
    id integer NOT NULL,
    game_mode smallint DEFAULT 0 NOT NULL,
    display_u_name boolean DEFAULT true NOT NULL,
    language character varying(16) DEFAULT 'en'::character varying NOT NULL,
    in_game_translate boolean DEFAULT true NOT NULL,
    pp_scoreboard boolean DEFAULT false NOT NULL,
    stealth_mode boolean DEFAULT false NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON COLUMN "user".settings.id IS 'user''s unique id';
CREATE TABLE "user".statistic (
    id integer NOT NULL,
    online_duration interval DEFAULT '00:00:00'::interval NOT NULL,
    login_count integer DEFAULT 0 NOT NULL,
    rename_count integer DEFAULT 0 NOT NULL,
    friends_count integer DEFAULT 0 NOT NULL,
    notes_count integer DEFAULT 0 NOT NULL,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".statistic IS 'User''s info statistic (such as online duration, etc.)';
COMMENT ON COLUMN "user".statistic.id IS 'user''s unique id';
COMMENT ON COLUMN "user".statistic.online_duration IS 'user''s total online duration';
COMMENT ON COLUMN "user".statistic.login_count IS 'user''s total login count';
COMMENT ON COLUMN "user".statistic.rename_count IS 'user''s total rename count';
COMMENT ON COLUMN "user".statistic.friends_count IS 'user''s total friend count';
COMMENT ON COLUMN "user".statistic.notes_count IS 'user''s total note count';
COMMENT ON COLUMN "user".statistic.update_time IS 'update time';
CREATE TABLE "user".status (
    id integer NOT NULL,
    credit integer DEFAULT 800 NOT NULL,
    is_bot boolean DEFAULT false NOT NULL,
    cheat integer DEFAULT 0 NOT NULL,
    multiaccount integer DEFAULT 0 NOT NULL,
    donor_start timestamp(6) with time zone,
    silence_start timestamp(6) with time zone,
    restrict_start timestamp(6) with time zone,
    ban_start timestamp(6) with time zone,
    donor_end timestamp(6) with time zone,
    silence_end timestamp(6) with time zone,
    restrict_end timestamp(6) with time zone,
    ban_end timestamp(6) with time zone,
    last_login_time timestamp(6) with time zone,
    discord_verifyed_time timestamp(6) with time zone,
    qq_verifyed_time timestamp(6) with time zone,
    official_verifyed_time timestamp(6) with time zone,
    osu_verifyed_time timestamp(6) with time zone,
    mail_verifyed_time timestamp(6) with time zone,
    update_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE "user".status IS 'User''s status info';
COMMENT ON COLUMN "user".status.id IS 'user_id, int 32, unique';
COMMENT ON COLUMN "user".status.is_bot IS 'is bot';
CREATE TABLE user_records.login (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    address_id integer NOT NULL,
    ip character varying(128) NOT NULL,
    version character varying(64) NOT NULL,
    similarity integer DEFAULT 101 NOT NULL,
    create_time timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    logout_time timestamp with time zone,
    online_duration interval
);
COMMENT ON TABLE user_records.login IS 'The user''s login record, associated with the user''s login address';
COMMENT ON COLUMN user_records.login.id IS 'login record id';
COMMENT ON COLUMN user_records.login.user_id IS 'user.id, int 32';
COMMENT ON COLUMN user_records.login.address_id IS 'user.address.id';
COMMENT ON COLUMN user_records.login.ip IS 'ip address';
COMMENT ON COLUMN user_records.login.version IS 'osu version';
COMMENT ON COLUMN user_records.login.similarity IS 'certainty of the address';
COMMENT ON COLUMN user_records.login.create_time IS 'create_time, auto';
COMMENT ON COLUMN user_records.login.logout_time IS 'this record''s logout time';
COMMENT ON COLUMN user_records.login.online_duration IS 'online duration';
CREATE SEQUENCE user_records.login_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE user_records.login_records_id_seq OWNED BY user_records.login.id;
CREATE TABLE user_records.rename (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    new_name character varying(64) NOT NULL,
    old_name character varying(64) NOT NULL,
    create_time timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
COMMENT ON TABLE user_records.rename IS 'Automatically record the user''s rename record (do not add manually)';
COMMENT ON COLUMN user_records.rename.id IS 'rename records id';
COMMENT ON COLUMN user_records.rename.user_id IS 'user''s unique id';
COMMENT ON COLUMN user_records.rename.new_name IS 'user''s new name (after rename)';
COMMENT ON COLUMN user_records.rename.old_name IS 'user''s old name (before rename)';
COMMENT ON COLUMN user_records.rename.create_time IS 'rename records create time';
CREATE SEQUENCE user_records.rename_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;
ALTER SEQUENCE user_records.rename_records_id_seq OWNED BY user_records.rename.id;
ALTER TABLE ONLY bancho.channels ALTER COLUMN id SET DEFAULT nextval('bancho.channels_id_seq'::regclass);
ALTER TABLE ONLY game_scores.catch ALTER COLUMN id SET DEFAULT nextval('game_scores.catch_id_seq'::regclass);
ALTER TABLE ONLY game_scores.catch_rx ALTER COLUMN id SET DEFAULT nextval('game_scores.catch_rx_id_seq'::regclass);
ALTER TABLE ONLY game_scores.mania ALTER COLUMN id SET DEFAULT nextval('game_scores.mania_id_seq'::regclass);
ALTER TABLE ONLY game_scores.std ALTER COLUMN id SET DEFAULT nextval('game_scores.std_id_seq'::regclass);
ALTER TABLE ONLY game_scores.std_ap ALTER COLUMN id SET DEFAULT nextval('game_scores.std_ap_id_seq'::regclass);
ALTER TABLE ONLY game_scores.std_rx ALTER COLUMN id SET DEFAULT nextval('game_scores.std_rx_id_seq'::regclass);
ALTER TABLE ONLY game_scores.std_scv2 ALTER COLUMN id SET DEFAULT nextval('game_scores.std_scv2_id_seq'::regclass);
ALTER TABLE ONLY game_scores.taiko ALTER COLUMN id SET DEFAULT nextval('game_scores.taiko_id_seq'::regclass);
ALTER TABLE ONLY game_scores.taiko_rx ALTER COLUMN id SET DEFAULT nextval('game_scores.taiko_rx_id_seq'::regclass);
ALTER TABLE ONLY "user".address ALTER COLUMN id SET DEFAULT nextval('"user".address_id_seq'::regclass);
ALTER TABLE ONLY "user".base ALTER COLUMN id SET DEFAULT nextval('"user".base_id_seq'::regclass);
ALTER TABLE ONLY "user".notes ALTER COLUMN id SET DEFAULT nextval('"user".notes_id_seq'::regclass);
ALTER TABLE ONLY user_records.login ALTER COLUMN id SET DEFAULT nextval('user_records.login_records_id_seq'::regclass);
ALTER TABLE ONLY user_records.rename ALTER COLUMN id SET DEFAULT nextval('user_records.rename_records_id_seq'::regclass);
INSERT INTO bancho.channels (id, name, title, read_priv, write_priv, auto_join, create_time, update_time) VALUES (1, '#osu', 'General discussion.', 1, 2, true, '2020-12-09 04:21:05.471552+08', '2020-12-09 04:21:14.652774+08');
INSERT INTO bancho.channels (id, name, title, read_priv, write_priv, auto_join, create_time, update_time) VALUES (4, '#lobby', 'Multiplayer lobby discussion room.', 1, 2, true, '2020-12-09 04:21:46.339821+08', '2020-12-09 04:21:46.339821+08');
INSERT INTO bancho.channels (id, name, title, read_priv, write_priv, auto_join, create_time, update_time) VALUES (3, '#announce', 'Exemplary performance and public announcements.', 1, 4, true, '2020-12-09 04:21:35.551317+08', '2021-01-04 21:29:59.518299+08');
INSERT INTO bancho.channels (id, name, title, read_priv, write_priv, auto_join, create_time, update_time) VALUES (5, '#开发', 'development', 1, 2, true, '2021-02-15 22:28:01.031559+08', '2021-02-15 22:28:37.085566+08');
INSERT INTO bancho.config (name, comment, enabled, update_time, settings) VALUES ('default', 'default config for you', true, '2021-04-21 20:06:12.387706+08', NULL);
INSERT INTO game_stats.catch (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.110564+08');
INSERT INTO game_stats.catch (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.115553+08');
INSERT INTO game_stats.catch (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.116908+08');
INSERT INTO game_stats.mania (id, total_score, ranked_score, pp_v1, pp_v2, playcount, total_hits, accuracy, max_combo, playtime, update_time) VALUES (6, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.110564+08');
INSERT INTO game_stats.mania (id, total_score, ranked_score, pp_v1, pp_v2, playcount, total_hits, accuracy, max_combo, playtime, update_time) VALUES (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.115553+08');
INSERT INTO game_stats.mania (id, total_score, ranked_score, pp_v1, pp_v2, playcount, total_hits, accuracy, max_combo, playtime, update_time) VALUES (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.116908+08');
INSERT INTO game_stats.std (id, total_score, ranked_score, total_score_rx, ranked_score_rx, total_score_ap, ranked_score_ap, total_score_scv2, ranked_score_scv2, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, pp_v1_ap, pp_v2_ap, pp_v2_scv2, playcount, playcount_rx, playcount_ap, playcount_scv2, total_hits, total_hits_rx, total_hits_ap, total_hits_scv2, accuracy, accuracy_rx, accuracy_ap, accuracy_scv2, max_combo, max_combo_rx, max_combo_ap, max_combo_scv2, playtime, playtime_rx, playtime_ap, playtime_scv2, update_time) VALUES (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.115553+08');
INSERT INTO game_stats.std (id, total_score, ranked_score, total_score_rx, ranked_score_rx, total_score_ap, ranked_score_ap, total_score_scv2, ranked_score_scv2, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, pp_v1_ap, pp_v2_ap, pp_v2_scv2, playcount, playcount_rx, playcount_ap, playcount_scv2, total_hits, total_hits_rx, total_hits_ap, total_hits_scv2, accuracy, accuracy_rx, accuracy_ap, accuracy_scv2, max_combo, max_combo_rx, max_combo_ap, max_combo_scv2, playtime, playtime_rx, playtime_ap, playtime_scv2, update_time) VALUES (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.116908+08');
INSERT INTO game_stats.std (id, total_score, ranked_score, total_score_rx, ranked_score_rx, total_score_ap, ranked_score_ap, total_score_scv2, ranked_score_scv2, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, pp_v1_ap, pp_v2_ap, pp_v2_scv2, playcount, playcount_rx, playcount_ap, playcount_scv2, total_hits, total_hits_rx, total_hits_ap, total_hits_scv2, accuracy, accuracy_rx, accuracy_ap, accuracy_scv2, max_combo, max_combo_rx, max_combo_ap, max_combo_scv2, playtime, playtime_rx, playtime_ap, playtime_scv2, update_time) VALUES (6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-04-01 16:24:23.015206+08');
INSERT INTO game_stats.taiko (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.110564+08');
INSERT INTO game_stats.taiko (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.115553+08');
INSERT INTO game_stats.taiko (id, total_score, ranked_score, total_score_rx, ranked_score_rx, pp_v1, pp_v2, pp_v1_rx, pp_v2_rx, playcount, playcount_rx, total_hits, total_hits_rx, accuracy, accuracy_rx, max_combo, max_combo_rx, playtime, playtime_rx, update_time) VALUES (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '2021-03-26 00:38:53.116908+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.1.0', 'PurePeace', NULL, 'initial', '2020-12-15 01:15:37.586205+08', '2020-12-20 01:13:47.84393+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.1.3', 'PurePeace', NULL, 'add game_scores, game_stats, modify some column', '2020-12-15 01:15:37.586205+08', '2020-12-15 01:15:52.635208+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.1.4', 'PurePeace', NULL, 'now, score v2 be as a standalone model', '2021-01-04 21:31:45.010709+08', '2021-01-04 21:31:45.010709+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.2.0', 'PurePeace', NULL, 'add bancho config!!!', '2021-02-14 12:35:34.687537+08', '2021-02-14 12:35:48.29814+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.2.1', 'PurePeace', NULL, 'modify', '2021-02-14 12:35:34.687537+08', '2021-02-14 12:35:48.29814+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.3.0', 'PurePeace', NULL, 'add beatmaps schema', '2021-03-16 04:17:59.07646+08', '2021-03-16 04:18:06.626569+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.4.0', 'PurePeace', NULL, 'add bancho.config 2 fields', '2021-03-25 22:38:16.399964+08', '2021-03-25 22:38:16.399964+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.4.1', 'PurePeace', NULL, 'modify user''s id start: 50 -> 100', '2021-03-25 22:39:18.328389+08', '2021-03-25 22:39:18.328389+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.5.0', 'PurePeace', NULL, 'game_scores add fields pp_v3; modify performance fields type from float -> jsonb', '2021-03-25 22:40:45.95958+08', '2021-03-25 22:40:45.95958+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.5.1', 'PurePeace', NULL, 'user.status -> user.info, modify user.settings', '2021-03-25 23:29:29.129352+08', '2021-03-25 23:29:53.324655+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.6.0', 'PurePeace', NULL, 'add auto insert triggers for user info, settings', '2021-03-26 00:39:55.096726+08', '2021-03-26 00:40:06.3158+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.6.1', 'PurePeace', NULL, 'modify user.info, user.notes', '2021-03-26 17:47:27.434628+08', '2021-03-26 17:47:27.434628+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.6.3', 'PurePeace', NULL, 'add config.enable_client_update', '2021-03-26 21:30:18.218534+08', '2021-03-26 21:30:18.218534+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.6.4', 'PurePeace', NULL, 'add beatmaps.ratings', '2021-03-27 10:16:11.720151+08', '2021-03-27 10:16:11.720151+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.6.5', 'PurePeace', NULL, 'modify beatmaps.statistic.playtime interval -> int8', '2021-03-27 14:22:34.605093+08', '2021-03-27 14:22:59.795308+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.7.0', 'PurePeace', NULL, 'done beatmaps.', '2021-03-28 10:38:16.374035+08', '2021-03-28 10:38:16.374035+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.7.1', 'PurePeace', NULL, 'add triggers', '2021-03-29 06:44:49.025951+08', '2021-03-29 06:44:49.025951+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.7.2', 'PurePeace', NULL, 'fix beatmap insert, work with on conflict', '2021-03-30 08:53:12.94511+08', '2021-03-30 08:53:12.94511+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.7.3', 'PurePeace', NULL, 'add config', '2021-03-31 00:13:02.334884+08', '2021-03-31 00:13:02.334884+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.8.0', 'PurePeace', NULL, 'game_scores all table add status, grade, client_flags', '2021-03-31 13:26:41.955093+08', '2021-03-31 13:26:41.955093+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.8.1', 'PurePeace', NULL, 'modify game_scores performance fields type', '2021-04-01 15:40:18.993189+08', '2021-04-01 15:40:18.993189+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.8.5', 'PurePeace', NULL, 'add score_triggers', '2021-04-02 03:27:14.388894+08', '2021-04-02 03:27:19.582632+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.0', 'PurePeace', NULL, 'add score validation, md5, rep_md5 and keys', '2021-04-14 17:19:53.277091+08', '2021-04-14 17:19:53.277091+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.1', 'PurePeace', NULL, 'modify score_triggers', '2021-04-19 04:23:59.33877+08', '2021-04-19 04:23:59.33877+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.2', 'PurePeace', NULL, 'Many updates', '2021-04-19 21:56:58.44226+08', '2021-04-19 21:56:58.44226+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.5', 'PurePeace', NULL, 'Many refactors. (stats)', '2021-04-20 04:56:03.104819+08', '2021-04-20 04:56:03.104819+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.6', 'PurePeace', NULL, 'Add u_name, modify user.info -> user.status', '2021-04-20 09:41:22.083242+08', '2021-04-20 09:41:24.354682+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.9.7', 'PurePeace', NULL, 'Modify beatmaps: remove server', '2021-04-21 03:29:58.900138+08', '2021-04-21 03:29:58.900138+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.10.0', 'PurePeace', NULL, 'Refactor: bancho config', '2021-04-21 20:21:10.927445+08', '2021-04-21 20:21:10.927445+08');
INSERT INTO public.db_versions (version, author, sql, release_note, create_time, update_time) VALUES ('0.10.1', 'PurePeace', NULL, 'modify bancho config trigger', '2021-04-27 00:17:17.105743+08', '2021-04-27 00:17:17.105743+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.1.2', 'PurePeace', '0.1.4', 'add tables', '2020-12-15 01:16:37.785543+08', '2021-01-04 21:32:36.894734+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.2.0', 'PurePeace', '0.2.0', 'add bancho config, spec, register', '2021-02-14 12:35:58.665894+08', '2021-02-22 22:26:20.630535+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.2.1', 'PurePeace', '0.2.1', '++', '2021-02-22 22:26:23.940376+08', '2021-03-25 22:41:55.65887+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.2.2', 'PurePeace', '0.3.0', '++', '2021-03-16 04:18:30.749606+08', '2021-03-25 22:41:58.095519+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.1.0', 'PurePeace', '0.1.0', 'initial', '2020-12-15 01:16:37.785543+08', '2021-03-25 22:42:05.808029+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.0', 'PurePeace', '0.5.0', '++', '2021-03-25 22:41:35.435096+08', '2021-03-25 23:30:13.073988+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.1', 'PurePeace', '0.5.1', '++', '2021-03-25 23:30:21.258548+08', '2021-03-25 23:30:21.258548+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.2', 'PurePeace', '0.6.0', '++', '2021-03-26 00:40:19.70588+08', '2021-03-26 00:40:27.59701+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.3', 'PurePeace', '0.6.1', '++', '2021-03-26 17:47:36.935998+08', '2021-03-26 17:47:36.935998+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.4', 'PurePeace', '0.6.3', '+', '2021-03-26 21:30:33.374054+08', '2021-03-26 21:30:33.374054+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.3.5', 'PurePeace', '0.6.5', '+++', '2021-03-27 10:16:26.051501+08', '2021-03-28 01:59:29.713373+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.5.0', 'PurePeace', '0.6.5', 'big refactor', '2021-03-28 01:59:32.294525+08', '2021-03-28 01:59:44.657543+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.5.5', 'PurePeace', '0.7.0', '+++', '2021-03-28 10:38:35.46138+08', '2021-03-28 10:38:38.685742+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.5.6', 'PurePeace', '0.7.1', '+', '2021-03-29 06:44:51.298491+08', '2021-03-29 06:44:51.298491+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.5.7', 'PurePeace', '0.7.2', '+', '2021-03-30 08:53:12.94511+08', '2021-03-30 08:53:12.94511+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.5.8', 'PurePeace', '0.7.3', '+', '2021-03-31 00:13:15.196893+08', '2021-03-31 00:13:17.098844+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.6.2', 'PurePeace', '0.8.0', '++++', '2021-03-31 15:26:49.524224+08', '2021-03-31 15:26:57.541795+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.6.3', 'PurePeace', '0.8.1', 'done get scoreboard', '2021-04-01 15:40:51.160652+08', '2021-04-01 15:40:51.160652+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.6.4', 'PurePeace', '0.8.5', 'auto personal best flag triggers', '2021-04-02 03:27:44.1726+08', '2021-04-02 03:27:44.1726+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.0', 'PurePeace', '0.9.0', '++ score submit', '2021-04-14 17:20:09.80058+08', '2021-04-14 17:20:09.80058+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.1', 'PurePeace', '0.9.1', 'modify score trigger', '2021-04-19 04:24:25.391+08', '2021-04-19 04:24:25.391+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.2', 'PurePeace', '0.9.2', '++', '2021-04-19 21:57:13.279349+08', '2021-04-19 21:57:13.279349+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.5', 'PurePeace', '0.9.5', 'score submit almost done!!', '2021-04-20 04:56:37.846606+08', '2021-04-20 04:56:37.846606+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.6', 'PurePeace', '0.9.6', 'optional unicode name support', '2021-04-20 09:41:44.570464+08', '2021-04-20 09:41:44.570464+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.7.7', 'PurePeace', '0.9.7', 'beatmaps edit', '2021-04-21 03:30:28.41399+08', '2021-04-21 03:30:28.41399+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.8.0', 'PurePeace', '0.10.0', 'Refactor bancho config', '2021-04-21 20:21:16.90335+08', '2021-04-21 20:21:16.90335+08');
INSERT INTO public.versions (version, author, db_version, release_note, create_time, update_time) VALUES ('0.10.1', 'PurePeace', '0.10.1', 'up to date', '2021-04-27 00:17:46.19709+08', '2021-04-27 00:17:46.19709+08');
INSERT INTO "user".base (id, name, name_safe, u_name, u_name_safe, password, email, privileges, country, create_time, update_time) VALUES (1, 'System', 'system', NULL, NULL, '$argon2i$v=19$m=4096,t=3,p=1$this_user_not_avalible_login', '#%system%#@*.%', 0, 'UN', '2021-01-04 21:43:45.770011+08', '2021-01-06 23:09:32.522439+08');
INSERT INTO "user".base (id, name, name_safe, u_name, u_name_safe, password, email, privileges, country, create_time, update_time) VALUES (6, 'ChinoChan', 'chinochan', NULL, NULL, '$argon2i$v=19$m=4096,t=3,p=1$bmVQNTdoZmdJSW9nMERsYWd4OGxRZ1hRSFpvUjg5TEs$H6OEckDS9yVSODESGYA2mPudB2UkoBUH8UhVB6B6Dsg', 'a@chino.com', 3, 'JP', '2020-12-19 21:35:54.465545+08', '2021-04-20 09:39:54.655107+08');
INSERT INTO "user".base (id, name, name_safe, u_name, u_name_safe, password, email, privileges, country, create_time, update_time) VALUES (5, 'PurePeace', 'purepeace', NULL, NULL, '$argon2i$v=19$m=4096,t=3,p=1$VGQ3NXNFbnV1a25hVHAzazZwRm80N3hROVFabHdmaHk$djMKitAp+E/PD56gyVnIeM/7HmJNM9xBt6h/yAuRqPk', '940857703@qq.com', 16387, 'CN', '2020-12-19 21:35:32.810099+08', '2021-04-20 09:39:57.277453+08');
INSERT INTO "user".settings (id, game_mode, display_u_name, language, in_game_translate, pp_scoreboard, stealth_mode, update_time) VALUES (6, 0, true, 'en', true, false, false, '2021-04-19 21:52:53.398096+08');
INSERT INTO "user".settings (id, game_mode, display_u_name, language, in_game_translate, pp_scoreboard, stealth_mode, update_time) VALUES (5, 0, true, 'en', true, false, false, '2021-04-19 21:52:53.398096+08');
INSERT INTO "user".settings (id, game_mode, display_u_name, language, in_game_translate, pp_scoreboard, stealth_mode, update_time) VALUES (1, 0, true, 'en', true, false, false, '2021-04-19 21:52:53.398096+08');
INSERT INTO "user".statistic (id, online_duration, login_count, rename_count, friends_count, notes_count, update_time) VALUES (1, '00:00:00', 0, 0, 0, 0, '2021-03-26 00:38:53.116908+08');
INSERT INTO "user".statistic (id, online_duration, login_count, rename_count, friends_count, notes_count, update_time) VALUES (6, '00:00:00', 0, 7, 0, 0, '2021-04-20 09:38:02.135604+08');
INSERT INTO "user".statistic (id, online_duration, login_count, rename_count, friends_count, notes_count, update_time) VALUES (5, '00:00:00', 0, 5, 0, 0, '2021-04-20 09:39:57.277453+08');
INSERT INTO "user".status (id, credit, is_bot, cheat, multiaccount, donor_start, silence_start, restrict_start, ban_start, donor_end, silence_end, restrict_end, ban_end, last_login_time, discord_verifyed_time, qq_verifyed_time, official_verifyed_time, osu_verifyed_time, mail_verifyed_time, update_time) VALUES (1, 800, false, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2021-03-26 17:49:46.00705+08');
INSERT INTO "user".status (id, credit, is_bot, cheat, multiaccount, donor_start, silence_start, restrict_start, ban_start, donor_end, silence_end, restrict_end, ban_end, last_login_time, discord_verifyed_time, qq_verifyed_time, official_verifyed_time, osu_verifyed_time, mail_verifyed_time, update_time) VALUES (5, 800, false, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2021-03-26 17:49:46.72318+08');
INSERT INTO "user".status (id, credit, is_bot, cheat, multiaccount, donor_start, silence_start, restrict_start, ban_start, donor_end, silence_end, restrict_end, ban_end, last_login_time, discord_verifyed_time, qq_verifyed_time, official_verifyed_time, osu_verifyed_time, mail_verifyed_time, update_time) VALUES (6, 800, false, 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2021-03-26 17:49:48.001861+08');
SELECT pg_catalog.setval('bancho.channels_id_seq', 5, true);
SELECT pg_catalog.setval('beatmaps.peace_bid', 1, false);
SELECT pg_catalog.setval('game_scores.catch_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.catch_rx_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.mania_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.std_ap_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.std_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.std_rx_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.std_scv2_id_seq', 1, false);
SELECT pg_catalog.setval('game_scores.taiko_id_seq', 1, true);
SELECT pg_catalog.setval('game_scores.taiko_rx_id_seq', 1, true);
SELECT pg_catalog.setval('"user".address_id_seq', 1, true);
SELECT pg_catalog.setval('"user".base_id_seq', 100, true);
SELECT pg_catalog.setval('"user".notes_id_seq', 1, true);
SELECT pg_catalog.setval('user_records.login_records_id_seq', 1, true);
SELECT pg_catalog.setval('user_records.rename_records_id_seq', 1, true);
ALTER TABLE ONLY bancho.channels
    ADD CONSTRAINT "channel.name" UNIQUE (name);
COMMENT ON CONSTRAINT "channel.name" ON bancho.channels IS 'channel name should be unique';
ALTER TABLE ONLY bancho.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);
ALTER TABLE ONLY bancho.config
    ADD CONSTRAINT config_pkey PRIMARY KEY (name);
ALTER TABLE ONLY beatmaps.stats
    ADD CONSTRAINT beatmap_md5 UNIQUE (md5);
ALTER TABLE ONLY beatmaps.maps
    ADD CONSTRAINT hash UNIQUE (md5);
ALTER TABLE ONLY beatmaps.maps
    ADD CONSTRAINT maps_pkey PRIMARY KEY (id);
ALTER TABLE ONLY beatmaps.ratings
    ADD CONSTRAINT ratings_pkey PRIMARY KEY (user_id, map_md5);
ALTER TABLE ONLY beatmaps.stats
    ADD CONSTRAINT statistic_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.catch
    ADD CONSTRAINT catch_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.catch
    ADD CONSTRAINT catch_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.catch_rx
    ADD CONSTRAINT catch_rx_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.catch_rx
    ADD CONSTRAINT catch_rx_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.catch_rx
    ADD CONSTRAINT catch_rx_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.catch
    ADD CONSTRAINT catch_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.mania
    ADD CONSTRAINT mania_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.mania
    ADD CONSTRAINT mania_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.mania
    ADD CONSTRAINT mania_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.std_ap
    ADD CONSTRAINT std_ap_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.std_ap
    ADD CONSTRAINT std_ap_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.std_ap
    ADD CONSTRAINT std_ap_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.std
    ADD CONSTRAINT std_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.std
    ADD CONSTRAINT std_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.std_rx
    ADD CONSTRAINT std_rx_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.std_rx
    ADD CONSTRAINT std_rx_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.std_rx
    ADD CONSTRAINT std_rx_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.std
    ADD CONSTRAINT std_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.std_scv2
    ADD CONSTRAINT std_scv2_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.std_scv2
    ADD CONSTRAINT std_scv2_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.std_scv2
    ADD CONSTRAINT std_scv2_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.taiko
    ADD CONSTRAINT taiko_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.taiko
    ADD CONSTRAINT taiko_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.taiko_rx
    ADD CONSTRAINT taiko_rx_md5 UNIQUE (md5);
ALTER TABLE ONLY game_scores.taiko_rx
    ADD CONSTRAINT taiko_rx_rep_md5 UNIQUE (rep_md5);
ALTER TABLE ONLY game_scores.taiko_rx
    ADD CONSTRAINT taiko_rx_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_scores.taiko
    ADD CONSTRAINT taiko_scores_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_stats.catch
    ADD CONSTRAINT catch_stats_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_stats.mania
    ADD CONSTRAINT mania_stats_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_stats.std
    ADD CONSTRAINT std_pkey PRIMARY KEY (id);
ALTER TABLE ONLY game_stats.taiko
    ADD CONSTRAINT taiko_stats_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.db_versions
    ADD CONSTRAINT db_versions_pkey PRIMARY KEY (version);
ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (version);
ALTER TABLE ONLY "user".notes
    ADD CONSTRAINT "Note.id" UNIQUE (id);
COMMENT ON CONSTRAINT "Note.id" ON "user".notes IS 'note id should be unique';
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT "Unique - email" UNIQUE (email);
COMMENT ON CONSTRAINT "Unique - email" ON "user".base IS 'email should be unique';
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT "Unique - name" UNIQUE (name);
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT "Unique - name safe" UNIQUE (name_safe);
COMMENT ON CONSTRAINT "Unique - name safe" ON "user".base IS 'name safe should be unique';
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT "Unique - u_name" UNIQUE (u_name);
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT "Unique - u_name safe" UNIQUE (u_name_safe);
COMMENT ON CONSTRAINT "Unique - u_name safe" ON "user".base IS 'uname safe should be unique';
ALTER TABLE ONLY "user".address
    ADD CONSTRAINT address_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "user".base
    ADD CONSTRAINT base_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "user".beatmap_collections
    ADD CONSTRAINT beatmap_collections_pkey PRIMARY KEY (user_id, beatmap_set_id);
ALTER TABLE ONLY "user".friends
    ADD CONSTRAINT friends_pkey PRIMARY KEY (user_id, friend_id);
ALTER TABLE ONLY "user".status
    ADD CONSTRAINT info_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "user".notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id, user_id);
ALTER TABLE ONLY "user".settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "user".statistic
    ADD CONSTRAINT statistic_pkey PRIMARY KEY (id);
ALTER TABLE ONLY user_records.login
    ADD CONSTRAINT login_records_pkey PRIMARY KEY (id);
ALTER TABLE ONLY user_records.rename
    ADD CONSTRAINT rename_records_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX beatmap_hash ON beatmaps.maps USING btree (md5);
CREATE INDEX beatmap_id ON beatmaps.maps USING btree (id);
CREATE UNIQUE INDEX "User.name" ON "user".base USING btree (name, name_safe);
CREATE INDEX user_address ON "user".address USING btree (user_id);
CREATE TRIGGER auto_update_time BEFORE UPDATE ON bancho.channels FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER bancho_config_trigger BEFORE INSERT OR UPDATE ON bancho.config FOR EACH ROW EXECUTE FUNCTION bancho.bancho_config_trigger();
CREATE TRIGGER auto_update_time BEFORE UPDATE ON beatmaps.ratings FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER auto_update_time BEFORE UPDATE ON beatmaps.stats FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER maps_trigger BEFORE INSERT OR UPDATE ON beatmaps.maps FOR EACH ROW EXECUTE FUNCTION beatmaps.beatmaps_map_trigger();
CREATE TRIGGER maps_trigger_after AFTER INSERT ON beatmaps.maps FOR EACH ROW EXECUTE FUNCTION beatmaps.beatmaps_map_trigger_after();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.catch FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.catch_rx FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.mania FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.std FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.std_ap FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.std_rx FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.std_scv2 FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.taiko FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER scores_trigger BEFORE INSERT OR UPDATE ON game_scores.taiko_rx FOR EACH ROW EXECUTE FUNCTION game_scores.scores_trigger();
CREATE TRIGGER auto_update_time BEFORE UPDATE ON game_stats.catch FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON game_stats.catch IS 'auto update the time';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON game_stats.mania FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON game_stats.mania IS 'auto update the time';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON game_stats.std FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON game_stats.std IS 'auto update the time';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON game_stats.taiko FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON game_stats.taiko IS 'auto update the time';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON public.db_versions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER auto_update_time BEFORE UPDATE ON public.versions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER auto_insert_related AFTER INSERT ON "user".base FOR EACH ROW EXECUTE FUNCTION "user".insert_related_on_base_insert();
COMMENT ON TRIGGER auto_insert_related ON "user".base IS 'auto insert into related table';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON "user".settings FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
CREATE TRIGGER auto_update_time BEFORE UPDATE ON "user".statistic FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON "user".statistic IS 'auto update the timestamp';
CREATE TRIGGER auto_update_time BEFORE UPDATE ON "user".status FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_time ON "user".status IS 'auto update time';
CREATE TRIGGER auto_update_timestamp BEFORE UPDATE ON "user".base FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER auto_update_timestamp ON "user".base IS 'auto update the update_time after update user info';
CREATE TRIGGER decrease_friend_count AFTER DELETE ON "user".friends FOR EACH ROW EXECUTE FUNCTION "user".decrease_friend_count();
COMMENT ON TRIGGER decrease_friend_count ON "user".friends IS 'update the statistic';
CREATE TRIGGER decrease_note_count AFTER DELETE ON "user".notes FOR EACH ROW EXECUTE FUNCTION "user".decrease_note_count();
COMMENT ON TRIGGER decrease_note_count ON "user".notes IS 'update the statistic';
CREATE TRIGGER increase_friend_count AFTER INSERT ON "user".friends FOR EACH ROW EXECUTE FUNCTION "user".increase_friend_count();
COMMENT ON TRIGGER increase_friend_count ON "user".friends IS 'update the statistic';
CREATE TRIGGER increase_note_count AFTER INSERT ON "user".notes FOR EACH ROW EXECUTE FUNCTION "user".increase_note_count();
COMMENT ON TRIGGER increase_note_count ON "user".notes IS 'update the statistic';
CREATE TRIGGER safe_user_info BEFORE INSERT OR UPDATE ON "user".base FOR EACH ROW EXECUTE FUNCTION "user".safe_user_info();
COMMENT ON TRIGGER safe_user_info ON "user".base IS 'auto make the user info safety';
CREATE TRIGGER update_time_auto BEFORE UPDATE ON "user".notes FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
COMMENT ON TRIGGER update_time_auto ON "user".notes IS 'auto update the update_time after update note info';
CREATE TRIGGER auto_login_duration BEFORE UPDATE ON user_records.login FOR EACH ROW EXECUTE FUNCTION user_records.auto_online_duration();
COMMENT ON TRIGGER auto_login_duration ON user_records.login IS 'auto update the online duration';
CREATE TRIGGER increase_login_count BEFORE INSERT ON user_records.login FOR EACH ROW EXECUTE FUNCTION user_records.increase_login_count();
COMMENT ON TRIGGER increase_login_count ON user_records.login IS 'auto update the statistic';
CREATE TRIGGER increase_rename_count BEFORE INSERT ON user_records.rename FOR EACH ROW EXECUTE FUNCTION user_records.increase_rename_count();
COMMENT ON TRIGGER increase_rename_count ON user_records.rename IS 'update user statistic';
ALTER TABLE ONLY beatmaps.ratings
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id" ON beatmaps.ratings IS 'user''s unique id';
ALTER TABLE ONLY beatmaps.stats
    ADD CONSTRAINT beatmap_hash FOREIGN KEY (md5) REFERENCES beatmaps.maps(md5) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.catch
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.catch_rx
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.mania
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.std
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.std_ap
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.std_rx
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.std_scv2
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.taiko
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_scores.taiko_rx
    ADD CONSTRAINT "user.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_stats.catch
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_stats.mania
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_stats.taiko
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY game_stats.std
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.versions
    ADD CONSTRAINT db_version FOREIGN KEY (db_version) REFERENCES public.db_versions(version) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE ONLY "user".friends
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id" ON "user".friends IS 'user_id';
ALTER TABLE ONLY "user".notes
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "user".address
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY "user".statistic
    ADD CONSTRAINT "User.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id" ON "user".statistic IS 'user''s unique id';
ALTER TABLE ONLY "user".beatmap_collections
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id" ON "user".beatmap_collections IS 'user_id';
ALTER TABLE ONLY "user".friends
    ADD CONSTRAINT "User.id (friend)" FOREIGN KEY (friend_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id (friend)" ON "user".friends IS 'user_id (friend)';
ALTER TABLE ONLY "user".status
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "user.id" ON "user".status IS 'user''s unique id';
ALTER TABLE ONLY "user".settings
    ADD CONSTRAINT "user.id" FOREIGN KEY (id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "user.id" ON "user".settings IS 'user''s unique id';
ALTER TABLE ONLY user_records.rename
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
COMMENT ON CONSTRAINT "User.id" ON user_records.rename IS 'user''s unique id';
ALTER TABLE ONLY user_records.login
    ADD CONSTRAINT "User.id" FOREIGN KEY (user_id) REFERENCES "user".base(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY user_records.login
    ADD CONSTRAINT "address.id" FOREIGN KEY (address_id) REFERENCES "user".address(id) ON UPDATE CASCADE ON DELETE CASCADE;
