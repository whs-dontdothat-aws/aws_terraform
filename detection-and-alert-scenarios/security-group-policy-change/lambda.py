
import os
import json
import urllib3

http = urllib3.PoolManager()
WEBHOOK = os.environ["DISCORD_WEBHOOK_URL"]

def lambda_handler(event, context):
    for rec in event["Records"]:
        try:
            msg = json.loads(rec["Sns"]["Message"])
        except Exception as e:
            print("SNS 메시지 파싱 실패:", str(e))
            continue

        detail = msg.get("detail", {})
        event_name = detail.get("eventName", "N/A")
        event_time_utc = msg.get("time", "N/A")
        event_time_kst = event_time_utc.replace("T", " ").replace("Z", "") if event_time_utc != "N/A" else "N/A"
        user_arn = detail.get("userIdentity", {}).get("arn", "N/A")
        source_ip = detail.get("sourceIPAddress", "N/A")
        aws_region = msg.get("region", "N/A")
        account_id = msg.get("account", "N/A")
        sg_id = "N/A"
        params = detail.get("requestParameters", {})
        if "groupId" in params:
            sg_id = params["groupId"]
        elif "groupIds" in params and isinstance(params["groupIds"], list):
            sg_id = ", ".join(params["groupIds"])

        content = (
            f"**[Security Group 변경 감지]**\n"
            f"• 이벤트 이름: `{event_name}`\n"
            f"• 보안 그룹 ID: `{sg_id}`\n"
            f"• 발생 시간(KST): `{event_time_kst}`\n"
            f"• 사용자 ARN: `{user_arn}`\n"
            f"• 소스 IP: `{source_ip}`\n"
            f"• 리전: `{aws_region}`\n"
            f"• 계정 ID: `{account_id}`"
        )

        http.request(
            "POST", WEBHOOK,
            body=json.dumps({"content": content}).encode(),
            headers={"Content-Type": "application/json"}
        )
