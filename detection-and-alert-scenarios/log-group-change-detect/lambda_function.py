import os, json, urllib3

http = urllib3.PoolManager()
WEBHOOK = os.environ["HOOK_URL"]

def lambda_handler(event, context):
    for rec in event["Records"]:
        msg = json.loads(rec["Sns"]["Message"])
        detail = msg.get("detail", {})

        content = (
            "CloudWatch Logs 변경 탐지\n"
            f"Event: {detail.get('eventName')}\n"
            f"LogGroup: {detail.get('requestParameters', {}).get('logGroupName', 'N/A')}\n"
            f"User: {detail.get('userIdentity', {}).get('arn', 'Unknown')}\n"
            f"Time: {msg.get('time')}"
        )
        http.request(
            "POST", WEBHOOK,
            body=json.dumps({"content": content}).encode(),
            headers={"Content-Type": "application/json"}
        )