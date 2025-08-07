import json
import urllib3
import os
import boto3
from datetime import datetime, timedelta

http = urllib3.PoolManager()
HOOK_URL = os.environ['DISCORD_WEBHOOK_URL']
INSTANCE_ID = os.environ['EC2_ID']  # 환경 변수에서 EC2 ID를 가져옴
ISOLATED_SG_ID = os.environ['ISOLATED_SG_ID']  # 격리용 보안 그룹 ID

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message = json.loads(record['Sns']['Message'])

            alarm_name = message.get("AlarmName", "Unknown Alarm")
            new_state = message.get("NewStateValue", "Unknown")
            reason = message.get("NewStateReason", "No reason provided")
            timestamp_utc = message.get("StateChangeTime", "")[:19]

            # 시간 변환: UTC → KST
            try:
                event_time_kst = datetime.strptime(timestamp_utc, '%Y-%m-%dT%H:%M:%S') + timedelta(hours=9)
                time_str = event_time_kst.strftime('%Y-%m-%d %H:%M:%S') + " (KST)"
            except:
                time_str = 'Unknown'

            snapshot_results = []
            sg_result = ""

            # EBS 스냅샷 생성
            try:
                volumes = ec2.describe_instances(InstanceIds=[INSTANCE_ID])['Reservations'][0]['Instances'][0]['BlockDeviceMappings']
                for v in volumes:
                    vol_id = v['Ebs']['VolumeId']
                    snap = ec2.create_snapshot(
                        VolumeId=vol_id,
                        Description=f"Auto Snapshot from alarm {alarm_name} on {INSTANCE_ID}"
                    )
                    snapshot_results.append(f"-EBS Snapshot 생성됨: {vol_id} → {snap['SnapshotId']}")
            except Exception as e:
                snapshot_results.append(f"스냅샷 생성 실패: {str(e)}")

            # EC2 인스턴스를 격리 보안 그룹으로 변경
            try:
                ec2.modify_instance_attribute(
                    InstanceId=INSTANCE_ID,
                    Groups=[ISOLATED_SG_ID]
                )
                sg_result = f" EC2 인스턴스 {INSTANCE_ID}의 보안 그룹이 격리 그룹({ISOLATED_SG_ID})으로 변경됨"
            except Exception as e:
                sg_result = f"보안 그룹 변경 실패: {str(e)}"

            # Discord 메시지 구성
            discord_msg = {
                "content": f"**[ bash_history 조작 탐지 알람 발생 ]**\n"
                           f"- 알람 이름: {alarm_name}\n"
                           f"- 상태: {new_state}\n"
                           f"- 이유: {reason}\n"
                           f"- 시간: {time_str}\n"
                           f"- EC2 인스턴스 ID: {INSTANCE_ID}\n\n"
                           f"{chr(10).join(snapshot_results)}\n"
                           f"{sg_result}"
            }

            encoded_msg = json.dumps(discord_msg).encode("utf-8")
            response = http.request(
                "POST",
                HOOK_URL,
                body=encoded_msg,
                headers={"Content-Type": "application/json"}
            )

            print(f"[Discord 응답] 상태 코드: {response.status}")

        return {"statusCode": 200, "body": "Success"}

    except Exception as e:
        print(f"[에러] {str(e)}")
        return {"statusCode": 500, "body": f"Error: {str(e)}"}
