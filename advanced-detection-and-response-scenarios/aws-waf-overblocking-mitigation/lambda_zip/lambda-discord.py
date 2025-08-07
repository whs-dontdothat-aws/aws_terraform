import json
import urllib.request
import os
import boto3

# 환경 변수 불러오기
WEBHOOK_URL = os.environ['WEBHOOK_URL']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')  

# SNS 클라이언트 생성
sns = boto3.client('sns')

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    # 이벤트에서 필요한 데이터 추출
    instance_id = event.get('instance_id', 'unknown')
    snapshot_id = event.get('snapshot_id', 'unknown')
    s3_bucket = event.get('s3_bucket', 'unknown')
    s3_prefix = event.get('s3_key_prefix', instance_id)
    isolation_status = event.get('isolation_status', '격리 완료')

    # Discord 메시지 내용 포맷 구성
    content = (
        "**[조치 완료 보고]**\n"
        "감염 인스턴스에 대한 자동 대응이 완료되었습니다.\n\n"
        f"• 인스턴스 ID: `{instance_id}`\n"
        f"• 격리 상태: {isolation_status}\n"
        f"• EBS 스냅샷 ID: `{snapshot_id}`\n"
        f"• 분석 로그 위치: `s3://{s3_bucket}/{s3_prefix}/`\n"
        f"• 담당자 확인 필요"
    )

    # Discord Webhook 요청 구성
    req = urllib.request.Request(
        WEBHOOK_URL,
        data=json.dumps({"content": content}).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req) as response:
            print(f"Webhook sent. Status: {response.status}")
    except Exception as e:
        print(f"Error sending webhook: {e}")
        raise


    # SNS 이메일 알림 전송
    if SNS_TOPIC_ARN:
        try:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="[조치 완료] 감염 인스턴스 자동 대응 결과",
                Message=content.replace("**", "")  # 이메일에 굵은 텍스트 제거
            )
            print(f"[SNS] Email notification sent via SNS.")
        except Exception as e:
            print(f"[SNS] Error sending SNS email: {e}")

    return {
        "status": "ok",
        "notified": True
    }