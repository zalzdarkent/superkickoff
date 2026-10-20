#!/usr/bin/env python3
"""Convert the original Spanish-schema database (2025_edit.db) into an
English-schema database (assets/data/superkickoff_2025.db).

Strategy:
  1. Copy the original DB file.
  2. Rename every table via ALTER TABLE ... RENAME TO.
  3. Rename every column via ALTER TABLE ... RENAME COLUMN.
     (SQLite >= 3.25 automatically rewrites references in triggers,
     views and index definitions.)
  4. Drop the old triggers/view and recreate them with English SQL.
  5. Rebuild named indexes with clean English names.
Requires: python3 with sqlite3 module compiled against SQLite >= 3.25.
"""

import os
import shutil
import sqlite3
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "..", "2025_edit.db")
DST_DIR = os.path.join(ROOT, "..", "assets", "data")
DST = os.path.join(DST_DIR, "superkickoff_2025.db")

# --------------------------------------------------------------- table renames
TABLES = {
    "eq_equipos": "teams",
    "eq_entrenadores": "coaches",
    "eq_estadios": "stadiums",
    "eq_equipos_jugadores": "team_players",
    "eq_equipos_cesiones": "team_loans",
    "paises": "countries",
    "pais_entrenador": "country_coaches",
    "pais_jugador_convocatoria": "country_callups",
    "jug_jugadores": "players",
    "jug_jugadores_habilidades": "player_skills",
    "jug_habilidades": "skills",
    "jug_posiciones": "positions",
    "jug_posiciones_habilidades": "position_skills",
    "jug_status": "player_statuses",
    "jus_stats": "player_season_stats",
    "jus_stats_paises": "player_season_stats_countries",
    "jug_contratos": "contracts",
    "jug_premios": "player_awards",
    "tor_torneos": "tournaments",
    "tor_torneos_paises": "tournament_countries",
    "tor_torneos_paises": "tournament_countries",
    "tor_divisiones": "divisions",
    "tor_grupos": "groups",
    "tor_temporadas": "seasons",
    "tor_temporadas_torneos": "season_tournaments",
    "tor_temporadas_equipos": "season_teams",
    "tor_temporada_paises": "season_countries",
    "tor_partidos": "matches",
    "tor_partidos_incidencias": "match_incidents",
    "tor_partidos_jugadores": "match_players",
    "tor_partidos_jugadores_paises": "match_players_countries",
    "tor_partidos_paises": "country_matches",
    "tor_arbitros": "referees",
    "tor_arbitros_tipos": "referee_types",
    "tor_inabilitados": "suspensions",
    "tor_cupos_internacionales": "international_slots",
    "tor_transferencias_jugadores": "player_transfers",
    "tor_transferencias_entrenadores": "coach_transfers",
    "Patrocinadores": "sponsors",
    "Patrocinios": "sponsorships",
    "mensajes": "messages",
    "historial_ranking_mundial": "world_ranking_history",
    "historial_user": "career_history",
}

# -------------------------------------------------------------- column renames
COLUMNS = {
    "teams": {
        "equid": "team_id", "equi_abrev": "abbreviation", "equi_nombre": "name",
        "equi_funda": "founded_year", "equi_valor": "value", "equi_poder": "power",
        "equi_presupuesto": "budget", "equi_pts": "points", "equi_estaid": "stadium_id",
        "equi_paid": "country_id", "equi_entid": "coach_id", "equi_division": "division",
    },
    "coaches": {
        "entid": "coach_id", "en_nombre": "name", "en_edad": "age",
        "en_paid": "country_id", "en_pts": "points",
    },
    "stadiums": {
        "estaid": "stadium_id", "es_nombre": "name",
        "es_tot_general": "capacity_general", "es_tot_plateas": "capacity_stand",
        "es_tot_tribunas": "capacity_terrace", "es_tot_palcos": "capacity_boxes",
        "es_max_general": "max_general", "es_max_plateas": "max_stand",
        "es_max_tribunas": "max_terrace", "es_max_palcos": "max_boxes",
        "es_paid": "country_id", "es_ciudad": "city",
    },
    "team_players": {"eqju_equid": "team_id", "eqju_jugid": "player_id"},
    "team_loans": {
        "ceid": "loan_id", "ces_jugid": "player_id",
        "ces_equid_origen": "from_team_id", "ces_equid_destino": "to_team_id",
        "ces_fecha_desde": "date_from", "ces_fecha_hasta": "date_to",
        "ces_meses": "months", "ces_mensaje": "notified",
    },
    "countries": {
        "paid": "country_id", "nombre": "name", "iso2": "iso2", "poder": "power",
        "pts": "points", "confederacion": "confederation",
    },
    "country_coaches": {
        "temporadaID": "season_id", "entrenadorID": "coach_id", "paisID": "country_id",
    },
    "country_callups": {
        "temporadaID": "season_id", "jugadorID": "player_id", "paisID": "country_id",
    },
    "players": {
        "jugid": "player_id", "jug_nombre": "name", "jug_edad": "age",
        "jug_estatura": "height", "jug_star": "stars", "jug_valor": "value",
        "jug_salario": "salary", "jug_perfil": "profile", "jug_experiencia": "experience",
        "jug_condicion": "fitness", "jug_jstdid": "status_id", "jug_poder": "power",
        "jug_potencial": "potential", "jug_mercado": "market_status",
        "jug_paid": "country_id", "jug_posid": "position_id", "jug_titular": "squad_status",
        "jug_capitan": "is_captain", "jug_numero": "shirt_number",
        "jug_campeonatos": "championships", "jug_pts": "points",
        "jug_habilidad_A": "skill_a", "jug_habilidad_B": "skill_b",
    },
    "player_skills": {
        "jh_jugid": "player_id", "jh_habid": "skill_id", "jh_poder": "power",
    },
    "skills": {"habid": "skill_id", "hab_nombre": "name", "hab_descripcion": "description"},
    "positions": {
        "posid": "position_id", "pos_abrev": "abbreviation", "pos_nombre": "name",
        "pos_tipo": "type",
    },
    "position_skills": {"ph_posid": "position_id", "ph_habid": "skill_id"},
    "player_statuses": {"jstdid": "status_id", "jstd_nombre": "name"},
    "player_season_stats": {
        "js_jugid": "player_id", "js_equid": "team_id", "js_tempid": "season_id",
        "js_pj": "matches_played", "js_min": "minutes", "js_cal": "rating",
        "js_titular": "starts", "js_amarillas": "yellow_cards", "js_rojas": "red_cards",
        "js_mvps": "mvps", "js_goles": "goals", "js_asistencias": "assists",
    },
    "player_season_stats_countries": {
        "js_jugid": "player_id", "js_paid": "country_id", "js_tempid": "season_id",
        "js_pj": "matches_played", "js_min": "minutes", "js_cal": "rating",
        "js_titular": "starts", "js_amarillas": "yellow_cards", "js_rojas": "red_cards",
        "js_mvps": "mvps", "js_goles": "goals", "js_asistencias": "assists",
    },
    "contracts": {
        "jc_id": "contract_id", "jc_jugid": "player_id", "jc_equid": "team_id",
        "jc_inicio": "start_date", "jc_fin": "end_date", "jc_status": "status",
        "jc_salario": "salary", "jc_bonoGol": "goal_bonus", "jc_bonoAsis": "assist_bonus",
        "jc_bonoMVP": "mvp_bonus", "jc_bonoCampe": "title_bonus",
        "jc_bonoPJ": "appearance_bonus",
    },
    "player_awards": {
        "premid": "award_id", "jugid": "player_id", "equid": "team_id", "tipo": "type",
        "anio": "year", "tempid": "season_id", "goles": "goals",
    },
    "tournaments": {
        "torid": "tournament_id", "tor_nombre": "name", "tor_idiv": "division_id",
        "tor_status": "status", "tor_organizacion": "organization", "tor_vueltas": "rounds",
        "tor_inverso": "reversed", "tor_fecha_1": "date_1", "tor_fecha_2": "date_2",
        "tor_label_1": "label_1", "tor_label_2": "label_2", "tor_dias": "play_days",
        "tor_cupos": "slots", "tor_pts": "points",
        "tor_asciende": "promotion_slots", "tor_desciende": "relegation_spots",
        "tor_premio_equipos": "prize_teams", "tor_premio_goleador": "prize_top_scorer",
        "tor_premio_mvps": "prize_mvp",
    },
    "tournament_countries": {
        "tp_paid": "country_id", "tp_torid": "tournament_id", "tp_cupos": "slots",
    },
    "divisions": {"idiv": "division_id", "div_nombre": "name"},
    "groups": {"gruid": "group_id", "gru_nombre": "name"},
    "seasons": {
        "tempid": "season_id", "tem_nombre": "name", "tem_anioinicio": "start_year",
        "tem_aniofin": "end_year", "tem_isNuevoFormato": "is_new_format",
    },
    "season_tournaments": {
        "tto_tempid": "season_id", "tto_torid": "tournament_id", "tto_status": "status",
    },
    "season_teams": {
        "te_equid": "team_id", "te_tempid": "season_id", "te_entid": "coach_id",
        "te_pos": "position",
    },
    "season_countries": {
        "tem_paid": "country_id", "tem_tempid": "season_id", "tem_entid": "coach_id",
        "tem_pos": "position",
    },
    "matches": {
        "partid": "match_id", "par_torid": "tournament_id", "par_tempid": "season_id",
        "par_arbid": "referee_id", "par_estaid": "stadium_id",
        "par_equid_local": "home_team_id", "par_equid_visita": "away_team_id",
        "par_goles_local": "home_goals", "par_goles_visita": "away_goals",
        "par_gana": "winner_id", "par_esp_general": "attendance_general",
        "par_esp_plateas": "attendance_stand", "par_esp_tribunas": "attendance_terrace",
        "par_esp_palcos": "attendance_boxes", "par_ent_ingresos": "revenue",
        "par_fase": "phase", "par_gruid": "group_id", "par_jornada": "round",
        "par_status": "status", "par_vuelta": "leg", "par_fecha": "date",
        "par_penal_goles_local": "penalty_home_goals",
        "par_penal_goles_visita": "penalty_away_goals",
    },
    "match_incidents": {"incid": "incident_id", "tpi_partid": "match_id", "tpi_json": "data"},
    "match_players": {
        "tpj_jugid": "player_id", "tpj_partid": "match_id", "tpj_equid": "team_id",
        "tpj_titular": "starter", "tpj_minutos": "minutes", "tpj_pts": "points",
        "tpj_calificacion": "rating", "tpj_mvp": "mvp", "tpj_goles": "goals",
        "tpj_amarillas": "yellow_cards", "tpj_rojas": "red_cards",
        "tpj_asistencias": "assists",
    },
    "match_players_countries": {
        "tpj_jugid": "player_id", "tpj_partid": "match_id", "tpj_paid": "country_id",
        "tpj_titular": "starter", "tpj_minutos": "minutes", "tpj_pts": "points",
        "tpj_calificacion": "rating", "tpj_mvp": "mvp", "tpj_goles": "goals",
        "tpj_amarillas": "yellow_cards", "tpj_rojas": "red_cards",
        "tpj_asistencias": "assists",
    },
    "country_matches": {
        "partid": "match_id", "par_torid": "tournament_id", "par_tempid": "season_id",
        "par_arbid": "referee_id", "par_estaid": "stadium_id",
        "par_pais_local": "home_country_id", "par_pais_visita": "away_country_id",
        "par_goles_local": "home_goals", "par_goles_visita": "away_goals",
        "par_gana": "winner_id", "par_esp_general": "attendance_general",
        "par_esp_plateas": "attendance_stand", "par_esp_tribunas": "attendance_terrace",
        "par_esp_palcos": "attendance_boxes", "par_ent_ingresos": "revenue",
        "par_fase": "phase", "par_jornada": "round", "par_status": "status",
        "par_vuelta": "leg", "par_fecha": "date",
        "par_penal_goles_local": "penalty_home_goals",
        "par_penal_goles_visita": "penalty_away_goals",
    },
    "referees": {
        "arbid": "referee_id", "abi_nombre": "name", "arb_paid": "country_id",
        "arb_tcaid": "type_id", "arb_edad": "age",
    },
    "referee_types": {"tcaid": "type_id", "tca_nombre": "name"},
    "suspensions": {
        "inaid": "suspension_id", "ina_jugid": "player_id", "ina_tipo": "type",
        "ina_jorinhabilitadas": "matches_remaining", "ina_tempid": "season_id",
    },
    "international_slots": {"torneoID": "tournament_id", "paisID": "country_id", "cupos": "slots"},
    "player_transfers": {
        "traid": "transfer_id", "tra_jugid": "player_id",
        "tra_equid_origen": "from_team_id", "tra_equid_destino": "to_team_id",
        "tra_tipo_transferencia": "type", "tra_valor": "value", "tra_fecha": "date",
    },
    "coach_transfers": {
        "teid": "transfer_id", "te_entid_despedido": "fired_coach_id",
        "te_entid_contratado": "hired_coach_id", "te_equid": "team_id",
        "te_tempid": "season_id", "te_fecha": "date",
    },
    "sponsors": {"Pa_ID": "sponsor_id", "Pa_nombre": "name", "Pa_nivel": "level"},
    "sponsorships": {
        "P_ID": "sponsorship_id", "P_tipo": "type", "P_equipoID": "team_id",
        "P_patrocinadorID": "sponsor_id", "P_torneoID": "tournament_id",
        "P_temporadaID": "season_id", "P_isPrioridad": "is_priority",
        "P_isPremioUnico": "is_unique_prize", "P_recompensaBase": "base_reward",
        "P_objetivo": "target", "P_cantidadLograda": "progress", "P_exito": "success",
        "P_status": "status", "P_dataExtra": "extra_data",
    },
    "messages": {
        "menid": "message_id", "titulo": "title", "mensaje": "body", "fecha": "date",
        "remitente": "sender", "visto": "is_read", "tipo": "type", "jugid": "player_id",
        "equid": "team_id", "costo": "cost", "acciones": "action", "respuesta": "response",
    },
    "world_ranking_history": {
        "rank_equipoid": "team_id", "rank_anio": "year", "rank_posicion": "position",
    },
    "career_history": {
        "h_tempid": "season_id", "h_entid": "coach_id", "h_equid": "team_id",
        "h_paid": "country_id", "h_pj": "matches_played", "h_pg": "wins",
        "h_pe": "draws", "h_pp": "losses", "h_gf": "goals_for", "h_gc": "goals_against",
        "h_anioInicio": "start_year", "h_anioFin": "end_year",
        "h_campeonatos": "championships",
    },
}

# Data-locale translations kept inside the DB (not schema, but keeps game UI clean).
SKILL_NAMES = {
    1: "Diving", 2: "Reflexes", 3: "Anticipation", 4: "Aerial Play", 5: "Positioning",
    6: "Tackling", 7: "Marking", 8: "Ball Recovery", 9: "Finishing", 10: "Heading",
    11: "Strength", 12: "Physique", 13: "Speed", 14: "Agility", 15: "Creativity",
    16: "Passing", 17: "Stamina", 18: "Free Kicks", 19: "Dribbling", 20: "Technique",
    21: "Leadership", 22: "Aggression", 23: "Intelligence", 24: "Ball Control",
    25: "Movement",
}

POSITION_NAMES = {
    1: ("GK", "Goalkeeper", 1), 2: ("CB", "Centre Back", 2),
    3: ("CB", "Sweeper Centre Back", 2), 4: ("FB", "Full Back", 2),
    5: ("DM", "Defensive Midfielder", 3), 6: ("AM", "Attacking Midfielder", 3),
    7: ("CM", "Central Midfielder", 3), 8: ("WM", "Wide Midfielder", 3),
    9: ("W", "Winger Forward", 4), 10: ("ST", "Striker", 4),
    11: ("SS", "Second Striker", 4),
}

DIVISION_NAMES = {
    1: "First Division", 2: "Second Division", 3: "Third Division",
    4: "Fourth Division", 0: "No Division",
}

PLAYER_STATUS_NAMES = {1: "Active", 2: "Retired", 3: "Dead"}

REFEREE_TYPE_NAMES = {
    1: "Lenient", 2: "Fair", 3: "Unsure", 4: "Bipolar", 5: "Grumpy",
}


def rename_tables(conn):
    for old, new in sorted(TABLES.items(), key=lambda kv: kv[1], reverse=True):
        conn.execute(f'ALTER TABLE "{old}" RENAME TO "{new}"')
        print(f"table: {old} -> {new}")


def rename_columns(conn):
    for table, cols in COLUMNS.items():
        for old, new in cols.items():
            existing = {row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')}
            if old not in existing:
                print(f"  ! skipped {table}.{old} (missing)", file=sys.stderr)
                continue
            conn.execute(f'ALTER TABLE "{table}" RENAME COLUMN "{old}" TO "{new}"')
        print(f"columns: {table}")


def rebuild_triggers_and_views(conn):
    # Legacy objects were dropped up-front by drop_legacy_objects();
    # here we recreate them with English SQL against the new names.

    conn.execute("CREATE VIEW IF NOT EXISTS v_countries AS SELECT\n"
                 "  c.country_id,\n"
                 "  c.name,\n"
                 "  c.power,\n"
                 "  (SELECT COUNT(*) FROM teams t\n"
                 "    JOIN countries cc ON cc.country_id = t.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS team_count,\n"
                 "  (SELECT MAX(t.power) FROM teams t\n"
                 "    JOIN countries cc ON cc.country_id = t.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS max_power,\n"
                 "  (SELECT MIN(t.power) FROM teams t\n"
                 "    JOIN countries cc ON cc.country_id = t.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS min_power,\n"
                 "  (SELECT COUNT(tu.tournament_id) FROM tournaments tu\n"
                 "    JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id\n"
                 "    JOIN countries cc ON cc.country_id = tc.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS tournament_count,\n"
                 "  (SELECT COUNT(*) FROM players p\n"
                 "    JOIN countries cc ON cc.country_id = p.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS country_players,\n"
                 "  (SELECT COUNT(*) FROM players p\n"
                 "    JOIN team_players tp ON tp.player_id = p.player_id\n"
                 "    JOIN teams t ON t.team_id = tp.team_id\n"
                 "    JOIN countries cc ON cc.country_id = t.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS league_players,\n"
                 "  (SELECT COUNT(*) FROM referees r\n"
                 "    JOIN countries cc ON cc.country_id = r.country_id\n"
                 "    WHERE cc.country_id = c.country_id) AS referee_count\n"
                 "FROM countries c\n"
                 "ORDER BY team_count DESC")

    conn.execute("""CREATE TRIGGER t_delete_old_messages
AFTER INSERT ON messages
BEGIN
    -- Keep only the 20 most recent messages.
    DELETE FROM messages
    WHERE message_id NOT IN (SELECT message_id FROM (SELECT message_id FROM messages ORDER BY message_id DESC LIMIT 20) temp);
END;""")

    conn.execute("""CREATE TRIGGER t_process_loans
AFTER INSERT ON season_teams
BEGIN
    -- market_status: 1 active, 2 for sale, 3 on loan
    -- squad_status:  0 reserve, 1 first team, 2 listed for loan
    UPDATE players SET squad_status = 1
    WHERE squad_status = 2 AND market_status != 3 AND player_id IN (
        SELECT p.player_id
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN teams t ON t.team_id = tp.team_id
        WHERE t.team_id = NEW.team_id)
    AND (
        SELECT CAST(IFNULL((SELECT tu.organization FROM seasons s
            JOIN season_tournaments st ON st.season_id = s.season_id
            JOIN tournaments tu ON tu.tournament_id = st.tournament_id
            WHERE s.season_id = NEW.season_id),0) AS INT));
    UPDATE players SET squad_status = 2 WHERE player_id IN (
        SELECT p.player_id
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN teams t ON t.team_id = tp.team_id
        WHERE t.team_id = NEW.team_id AND p.player_id NOT IN (
            SELECT p.player_id
            FROM players p
            JOIN team_players tp ON tp.player_id = p.player_id
            JOIN teams t ON t.team_id = tp.team_id
            WHERE t.team_id = NEW.team_id
            ORDER BY p.power DESC
            LIMIT 6)
        AND (
            SELECT CAST(IFNULL((SELECT tu.organization FROM seasons s
                JOIN season_tournaments st ON st.season_id = s.season_id
                JOIN tournaments tu ON tu.tournament_id = st.tournament_id
                WHERE s.season_id = NEW.season_id),0) AS INT)
            ) = 1
        AND (
            SELECT COUNT(p.player_id)
            FROM players p
            JOIN team_players tp ON tp.player_id = p.player_id
            JOIN teams t ON t.team_id = tp.team_id
            WHERE t.team_id = NEW.team_id
              AND p.squad_status <= 1 AND p.market_status = 1
        ) > 20
        ORDER BY RANDOM()
        LIMIT 0,(SELECT ABS(RANDOM() % 2)));
END;""")

    conn.execute("""CREATE TRIGGER t_sell_players
AFTER INSERT ON season_teams
BEGIN
    -- market_status: 1 active, 2 for sale, 3 on loan
    -- squad_status:  0 reserve, 1 first team, 2 listed for loan
    UPDATE players SET market_status = 1
    WHERE market_status = 2 AND player_id IN (
        SELECT p.player_id
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN teams t ON t.team_id = tp.team_id
        WHERE t.team_id = NEW.team_id)
    AND (
        SELECT CAST(IFNULL((SELECT tu.organization FROM seasons s
            JOIN season_tournaments st ON st.season_id = s.season_id
            JOIN tournaments tu ON tu.tournament_id = st.tournament_id
            WHERE s.season_id = NEW.season_id),0) AS INT)
        ) = 1
    AND (
        SELECT COUNT(p.player_id)
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN teams t ON t.team_id = tp.team_id
        WHERE t.team_id = NEW.team_id AND p.squad_status <= 1 AND p.market_status = 1
    ) > 20;
    UPDATE players SET market_status = 2 WHERE player_id IN (
        SELECT p.player_id
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN teams t ON t.team_id = tp.team_id
        WHERE t.team_id = NEW.team_id AND p.player_id NOT IN (
            SELECT p.player_id
            FROM players p
            JOIN team_players tp ON tp.player_id = p.player_id
            JOIN teams t ON t.team_id = tp.team_id
            WHERE t.team_id = NEW.team_id
            ORDER BY p.power DESC
            LIMIT 6)
        AND (
            SELECT CAST(IFNULL((SELECT tu.organization FROM seasons s
                JOIN season_tournaments st ON st.season_id = s.season_id
                JOIN tournaments tu ON tu.tournament_id = st.tournament_id
                WHERE s.season_id = NEW.season_id),0) AS INT)
            ) = 1
        AND (
            SELECT COUNT(p.player_id)
            FROM players p
            JOIN team_players tp ON tp.player_id = p.player_id
            JOIN teams t ON t.team_id = tp.team_id
            WHERE t.team_id = NEW.team_id
              AND p.squad_status <= 1 AND p.market_status = 1
        ) > 20
        ORDER BY RANDOM()
        LIMIT 0,(SELECT ABS(RANDOM() % 4)));
END;""")

    conn.execute("""CREATE TRIGGER t_clear_season
BEFORE UPDATE OF status ON season_tournaments
WHEN NEW.status = 0
BEGIN
    -- 1. Archive the season summary into player_season_stats
    INSERT INTO player_season_stats (player_id, team_id, season_id, matches_played, minutes, rating, starts, yellow_cards, red_cards, mvps, goals, assists)
    SELECT
        p.player_id, t.team_id, s.season_id,
        COUNT(CASE WHEN mp.minutes > 0 THEN 1 ELSE NULL END),
        SUM(mp.minutes), SUM(mp.rating),
        SUM(CASE WHEN mp.starter = 1 THEN 1 ELSE 0 END),
        IFNULL(SUM(mp.yellow_cards),0), IFNULL(SUM(mp.red_cards),0),
        IFNULL(SUM(CASE WHEN mp.mvp = 1 THEN 1 ELSE 0 END),0),
        IFNULL(SUM(mp.goals),0), IFNULL(SUM(mp.assists),0)
    FROM players p
    JOIN match_players mp ON mp.player_id = p.player_id
    JOIN matches m ON m.match_id = mp.match_id
    JOIN seasons s ON s.season_id = m.season_id
    JOIN season_tournaments st ON st.season_id = s.season_id
    JOIN tournaments tu ON tu.tournament_id = st.tournament_id
    JOIN teams t ON t.team_id = mp.team_id
    WHERE s.season_id = NEW.season_id
    GROUP BY p.player_id;
    -- 2. Remove the aggregated per-match rows
    DELETE FROM match_players WHERE match_id IN (
        SELECT m.match_id
        FROM matches m
        JOIN seasons s ON s.season_id = m.season_id
        WHERE s.season_id = NEW.season_id);
    -- 3. Remove the season incidents
    DELETE FROM match_incidents WHERE match_id IN (
        SELECT m.match_id
        FROM matches m
        JOIN seasons s ON s.season_id = m.season_id
        WHERE s.season_id = NEW.season_id);
END;""")

    conn.execute("""CREATE TRIGGER t_clear_season_countries
BEFORE UPDATE OF status ON season_tournaments
WHEN NEW.status = 0
BEGIN
    INSERT INTO player_season_stats_countries (player_id, country_id, season_id, matches_played, minutes, rating, starts, yellow_cards, red_cards, mvps, goals, assists)
    SELECT
        p.player_id, p.country_id, s.season_id,
        COUNT(CASE WHEN mpc.minutes > 0 THEN 1 ELSE NULL END),
        SUM(mpc.minutes), SUM(mpc.rating),
        SUM(CASE WHEN mpc.starter = 1 THEN 1 ELSE 0 END),
        IFNULL(SUM(mpc.yellow_cards),0), IFNULL(SUM(mpc.red_cards),0),
        IFNULL(SUM(CASE WHEN mpc.mvp = 1 THEN 1 ELSE 0 END),0),
        IFNULL(SUM(mpc.goals),0), IFNULL(SUM(mpc.assists),0)
    FROM players p
    INNER JOIN match_players_countries mpc ON mpc.player_id = p.player_id
    INNER JOIN country_matches cm ON cm.match_id = mpc.match_id
    INNER JOIN seasons s ON s.season_id = cm.season_id
    INNER JOIN season_tournaments st ON st.season_id = s.season_id
    INNER JOIN tournaments tu ON tu.tournament_id = st.tournament_id
    INNER JOIN countries c ON c.country_id = mpc.country_id
    WHERE s.season_id = NEW.season_id
    GROUP BY p.player_id;
    DELETE FROM match_players_countries WHERE match_id IN (
        SELECT cm.match_id
        FROM country_matches cm
        INNER JOIN seasons s ON s.season_id = cm.season_id
        WHERE s.season_id = NEW.season_id);
END;""")
    print("created English triggers + v_countries")


def rebuild_indexes(conn):
    old_index_names = [row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'")]
    for name in old_index_names:
        conn.execute(f'DROP INDEX "{name}"')
    stmts = [
        "CREATE INDEX idx_coaches_id ON coaches (coach_id)",
        "CREATE INDEX idx_teams_id ON teams (team_id)",
        "CREATE INDEX idx_teams_country ON teams (country_id)",
        "CREATE INDEX idx_teams_coach ON teams (coach_id)",
        "CREATE INDEX idx_teams_stadium ON teams (stadium_id)",
        "CREATE INDEX idx_team_players_team ON team_players (team_id)",
        "CREATE INDEX idx_team_players_player ON team_players (player_id)",
        "CREATE INDEX idx_stadiums_id ON stadiums (stadium_id)",
        "CREATE INDEX idx_players_id ON players (player_id)",
        "CREATE INDEX idx_players_country ON players (country_id)",
        "CREATE INDEX idx_players_position ON players (position_id)",
        "CREATE INDEX idx_player_season_stats_season ON player_season_stats (season_id)",
        "CREATE INDEX idx_player_season_stats_player ON player_season_stats (player_id)",
        "CREATE INDEX idx_referees_id ON referees (referee_id)",
        "CREATE INDEX idx_matches_id ON matches (match_id)",
        "CREATE INDEX idx_matches_tournament ON matches (tournament_id)",
        "CREATE INDEX idx_matches_season ON matches (season_id)",
        "CREATE INDEX idx_matches_home ON matches (home_team_id)",
        "CREATE INDEX idx_matches_away ON matches (away_team_id)",
        "CREATE INDEX idx_matches_referee ON matches (referee_id)",
        "CREATE INDEX idx_matches_stadium ON matches (stadium_id)",
        "CREATE INDEX idx_match_players_match ON match_players (match_id)",
        "CREATE INDEX idx_match_players_player ON match_players (player_id)",
        "CREATE INDEX idx_match_players_team ON match_players (team_id)",
        "CREATE INDEX idx_season_teams_team ON season_teams (team_id)",
        "CREATE INDEX idx_season_teams_season ON season_teams (season_id)",
        "CREATE INDEX idx_season_teams_coach ON season_teams (coach_id)",
        "CREATE INDEX idx_season_tournaments_season ON season_tournaments (season_id)",
        "CREATE INDEX idx_season_tournaments_tournament ON season_tournaments (tournament_id)",
        "CREATE INDEX idx_tournaments_id ON tournaments (tournament_id)",
        "CREATE INDEX idx_tournament_countries_tournament ON tournament_countries (tournament_id)",
        "CREATE INDEX idx_tournament_countries_country ON tournament_countries (country_id)",
    ]
    for sql in stmts:
        conn.execute(sql)
    print(f"rebuilt {len(old_index_names)} -> {len(stmts)} indexes")


def translate_reference_data(conn):
    for sid, name in SKILL_NAMES.items():
        conn.execute("UPDATE skills SET name=? WHERE skill_id=?", (name, sid))
    for pid, (abrv, name, ptype) in POSITION_NAMES.items():
        conn.execute("UPDATE positions SET abbreviation=?, name=?, type=? WHERE position_id=?",
                     (abrv, name, ptype, pid))
    for did, name in DIVISION_NAMES.items():
        conn.execute("UPDATE divisions SET name=? WHERE division_id=?", (name, did))
    for sid, name in PLAYER_STATUS_NAMES.items():
        conn.execute("UPDATE player_statuses SET name=? WHERE status_id=?", (name, sid))
    for tid, name in REFEREE_TYPE_NAMES.items():
        conn.execute("UPDATE referee_types SET name=? WHERE type_id=?", (name, tid))
    print("translated reference data (skills, positions, divisions, statuses) to English")


def drop_legacy_objects(conn):
    # Drop BEFORE renaming: SQLite validates trigger SQL on ALTER, and the old
    # Spanish triggers contain ambiguous bare column names once columns are
    # renamed (e.g. `paid` exists in several joined tables).
    for name in ("tDeleteOldMensajes", "tCederJugadores", "tVenderJugadores",
                 "tLimpiarTemporada", "tLimpiarTemporadaPaises"):
        conn.execute(f'DROP TRIGGER IF EXISTS "{name}"')
    conn.execute("DROP VIEW IF EXISTS vPaises")
    print("dropped legacy triggers + vPaises")


def main():
    if os.path.exists(DST):
        os.remove(DST)
    os.makedirs(DST_DIR, exist_ok=True)
    shutil.copyfile(SRC, DST)
    conn = sqlite3.connect(DST)
    sqlite_version = sqlite3.sqlite_version
    print(f"SQLite runtime: {sqlite_version}")
    major, minor = int(sqlite_version.split(".")[0]), int(sqlite_version.split(".")[1])
    if (major, minor) < (3, 25):
        sys.exit("ERROR: SQLite >= 3.25 required for RENAME COLUMN")
    with conn:
        drop_legacy_objects(conn)
        rename_tables(conn)
        rename_columns(conn)
        rebuild_triggers_and_views(conn)
        rebuild_indexes(conn)
        translate_reference_data(conn)
    # sanity checks
    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    expected_spanish = [t for t in TABLES if t in tables]
    if expected_spanish:
        sys.exit(f"ERROR: still present: {expected_spanish}")
    if "v_countries" not in {row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='view'")}:
        sys.exit("ERROR: v_countries missing")
    stand = conn.execute("SELECT team.name FROM teams team LIMIT 1").fetchall()
    print("sanity query OK:", stand)
    print("events(paises)", conn.execute("SELECT COUNT(*) FROM countries").fetchone())
    size_mb = os.path.getsize(DST) / 1e6
    print(f"DONE -> {DST} ({size_mb:.1f} MB)")
    conn.close()


if __name__ == "__main__":
    main()
