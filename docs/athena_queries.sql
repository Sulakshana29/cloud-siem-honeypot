-- ============================================================
-- Cloud SIEM Honeypot — Athena Threat Hunting Queries
-- Database:   cloud_siem_db
-- Table:      cowrie_logs
-- Workgroup:  cloud-siem-workgroup
--
-- USAGE: In the Athena console, select:
--   Database  -> cloud_siem_db
--   Workgroup -> cloud-siem-workgroup
-- Then paste and run any query below.
-- ============================================================


-- 1. SANITY CHECK: Latest Events
-- Run this first to confirm data is flowing from the honeypot.

SELECT timestamp, event_type, src_ip, username, password
FROM cloud_siem_db.cowrie_logs
ORDER BY timestamp DESC
LIMIT 20;


-- 2. TOP 20 ATTACKING IPs (by login attempts)
-- Reveals the most aggressive scanners / botnets.

SELECT
    src_ip,
    COUNT(*)                                          AS total_attempts,
    COUNT(CASE WHEN event_type = 'cowrie.login.success' THEN 1 END) AS successes,
    COUNT(CASE WHEN event_type = 'cowrie.login.failed'  THEN 1 END) AS failures,
    MIN(timestamp)                                    AS first_seen,
    MAX(timestamp)                                    AS last_seen
FROM cloud_siem_db.cowrie_logs
WHERE event_type IN ('cowrie.login.failed', 'cowrie.login.success')
GROUP BY src_ip
ORDER BY total_attempts DESC
LIMIT 20;


-- 3. MOST TRIED USERNAME / PASSWORD COMBINATIONS
-- Shows exactly what credentials attackers spray most.

SELECT
    username,
    password,
    COUNT(*) AS attempts,
    COUNT(DISTINCT src_ip) AS unique_ips
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.login.failed'
  AND username IS NOT NULL
  AND username != ''
GROUP BY username, password
ORDER BY attempts DESC
LIMIT 30;


-- 4. SUCCESSFUL LOGINS - Full Session Detail
-- Every success means an attacker got past auth (into Cowrie's fake shell).

SELECT
    timestamp,
    src_ip,
    src_port,
    username,
    password,
    session_id
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.login.success'
ORDER BY timestamp DESC;


-- 5. COMMANDS RUN AFTER SUCCESSFUL LOGIN
-- What do attackers DO once they're "in"?

SELECT
    timestamp,
    src_ip,
    session_id,
    command
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.command.input'
  AND command IS NOT NULL
  AND command != ''
ORDER BY timestamp DESC
LIMIT 100;


-- 6. MOST COMMON POST-LOGIN COMMANDS
-- Aggregated view of attacker TTPs (Tactics, Techniques, Procedures).

SELECT
    command,
    COUNT(*)              AS times_run,
    COUNT(DISTINCT src_ip) AS unique_attackers
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.command.input'
  AND command IS NOT NULL
GROUP BY command
ORDER BY times_run DESC
LIMIT 30;


-- 7. MALWARE DOWNLOAD ATTEMPTS
-- file_sha is SHA256 of the file -- look up in VirusTotal for threat intel.

SELECT
    timestamp,
    src_ip,
    session_id,
    file_url,
    file_sha,
    file_size
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.session.file_download'
ORDER BY timestamp DESC;


-- 8. ATTACK TIMELINE FOR A SPECIFIC SESSION
-- Deep-dive on a single attacker session. Replace the session_id value.
-- Reconstructs the full kill chain: connect -> auth -> commands -> download -> exit.

SELECT
    timestamp,
    event_type,
    src_ip,
    username,
    password,
    command,
    file_url,
    message
FROM cloud_siem_db.cowrie_logs
WHERE session_id = 'REPLACE_WITH_SESSION_ID'
ORDER BY timestamp ASC;


-- 9. DAILY ATTACK VOLUME
-- Spot attack spikes -- are more attacks happening on specific days?

SELECT
    year,
    month,
    day,
    COUNT(*)                                           AS total_events,
    COUNT(DISTINCT src_ip)                             AS unique_ips,
    COUNT(CASE WHEN event_type = 'cowrie.login.success' THEN 1 END) AS successful_logins
FROM cloud_siem_db.cowrie_logs
GROUP BY year, month, day
ORDER BY year DESC, month DESC, day DESC;


-- 10. UNIQUE ATTACKER IPs PER DAY
-- Rising unique IPs = coordinated campaign or new botnet targeting you.

SELECT
    year,
    month,
    day,
    COUNT(DISTINCT src_ip) AS unique_attacking_ips
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.session.connect'
GROUP BY year, month, day
ORDER BY year DESC, month DESC, day DESC;


-- 11. ATTACKER SESSION DURATION
-- Long sessions = engaged human attacker. Short = automated scanner.

WITH session_times AS (
    SELECT
        session_id,
        src_ip,
        MIN(timestamp) AS session_start,
        MAX(timestamp) AS session_end
    FROM cloud_siem_db.cowrie_logs
    WHERE event_type IN ('cowrie.session.connect', 'cowrie.session.closed')
    GROUP BY session_id, src_ip
)
SELECT
    session_id,
    src_ip,
    session_start,
    session_end
FROM session_times
ORDER BY session_start DESC
LIMIT 50;


-- 12. DESTINATION PORT TARGETING
-- Which ports are attackers hitting? Should be mostly 2222 and 23 (Cowrie).

SELECT
    dst_port,
    COUNT(*) AS connections,
    COUNT(DISTINCT src_ip) AS unique_ips
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.session.connect'
GROUP BY dst_port
ORDER BY connections DESC;
