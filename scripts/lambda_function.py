import json
import base64
import gzip
import os
import boto3
from datetime import datetime, timezone

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ.get('S3_BUCKET_NAME')

RELEVANT_EVENTS = {
    "cowrie.session.connect",
    "cowrie.login.failed",
    "cowrie.login.success",
    "cowrie.command.input",
    "cowrie.session.file_download",
    "cowrie.session.closed",
}

def normalize_event(raw: dict) -> dict | None:
    event_id = raw.get("eventid", "")
    if event_id not in RELEVANT_EVENTS:
        return None

    raw_ts = raw.get("timestamp", "")
    try:
        ts = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
        normalized_ts = ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    except (ValueError, AttributeError):
        normalized_ts = raw_ts

    normalized = {
        "timestamp":    normalized_ts,
        "source":       "cowrie-honeypot",
        "event_type":   event_id,
        "session_id":   raw.get("session", ""),
        "src_ip":       raw.get("src_ip", ""),
        "src_port":     raw.get("src_port", 0),
        "dst_port":     raw.get("dst_port", 0),
        "username":     raw.get("username", ""),
        "password":     raw.get("password", ""),
        "command":      raw.get("input", ""),
        "message":      raw.get("message", ""),
        "sensor":       raw.get("sensor", ""),
    }

    if event_id == "cowrie.session.file_download":
        normalized["file_url"]  = raw.get("url", "")
        normalized["file_sha"]  = raw.get("shasum", "")
        normalized["file_size"] = raw.get("outfile", "")

    return normalized

def lambda_handler(event, context):
    try:
        # CloudWatch Logs sends a base64 encoded, gzip compressed payload
        cw_data = event['awslogs']['data']
        compressed_payload = base64.b64decode(cw_data)
        uncompressed_payload = gzip.decompress(compressed_payload)
        payload = json.loads(uncompressed_payload)

        log_events = payload.get('logEvents', [])
        normalized_records = []

        for log_event in log_events:
            try:
                raw_message = json.loads(log_event['message'])
                clean_record = normalize_event(raw_message)
                if clean_record:
                    normalized_records.append(clean_record)
            except json.JSONDecodeError:
                continue

        if normalized_records:
            # Create a unique filename based on the current timestamp
            timestamp_str = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
            s3_key = f"logs/year={timestamp_str[:4]}/month={timestamp_str[4:6]}/day={timestamp_str[6:8]}/cowrie_{timestamp_str}.json"
            
            s3_body = "\n".join([json.dumps(r) for r in normalized_records])
            
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=s3_body,
                ContentType='application/json'
            )
            print(f"Successfully processed {len(normalized_records)} events and uploaded to s3://{BUCKET_NAME}/{s3_key}")
        
        return {
            'statusCode': 200,
            'body': f'Processed {len(normalized_records)} records.'
        }

    except Exception as e:
        print(f"Error processing logs: {e}")
        raise e
