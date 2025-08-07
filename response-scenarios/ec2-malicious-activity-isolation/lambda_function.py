import json
import os
import boto3
import urllib3

ec2 = boto3.client('ec2')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    webhook_url = os.environ['DISCORD_WEBHOOK_URL']
    quarantine_sg_id = os.environ['QUARANTINE_SG_ID']

    for record in event['Records']:
        try:
            message = json.loads(record['Sns']['Message'])
            detail = message.get("detail", {})
            instance_id = detail.get("resource", {}).get("instanceDetails", {}).get("instanceId")
            finding_type = detail.get("type", "Unknown")
            severity = detail.get("severity", "N/A")
            region = message.get("region", "Unknown")

            # Discord 메시지 내용 생성
            content = f"🚨 **GuardDuty Alert**\n" \
                      f"- Type: `{finding_type}`\n" \
                      f"- Severity: `{severity}`\n" \
                      f"- Region: `{region}`\n" \
                      f"- Instance ID: `{instance_id}`"

            # EC2 인스턴스 격리
            if instance_id:
                ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'quarantined', 'Value': 'true'}])
                ec2.modify_instance_attribute(InstanceId=instance_id, Groups=[quarantine_sg_id])
                content += "\n🛡️ EC2 instance has been isolated using the quarantine security group."

        except Exception as e:
            content = f"❌ Error processing GuardDuty event: {e}"

        # Discord Webhook 전송
        try:
            http.request(
                "POST",
                webhook_url,
                body=json.dumps({"content": content}).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
        except Exception as e:
            print(f"❌ Failed to send message to Discord: {e}")
