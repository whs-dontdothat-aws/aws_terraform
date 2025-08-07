import json
import boto3
import datetime
import os

s3 = boto3.client('s3')
# 환경변수로 S3 버킷명 prefix를 관리
BUCKET = os.environ.get('S3_BUCKET', 'your-guardduty-logs-bucket')
PREFIX = os.environ.get('S3_PREFIX', 'guardduty/finding-logs/')

def lambda_handler(event, context):
    # 파일명에 타임스탬프와 랜덤성을 추가
    timestamp = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    unique = context.aws_request_id if hasattr(context, 'aws_request_id') else 'unknown'
    key = f"{PREFIX}{timestamp}_{unique}.json"

    # S3에 저장할 JSON(이벤트 원본 저장)
    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=json.dumps(event, ensure_ascii=False, indent=2),
        ContentType='application/json'
    )
    return {
        'statusCode': 200,
        'body': f"Saved finding to {BUCKET}/{key}"
    }
