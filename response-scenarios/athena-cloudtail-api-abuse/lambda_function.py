import boto3
import json
import urllib3
import time
import os
from datetime import datetime, timedelta

# AWS 클라이언트
athena = boto3.client('athena')
sns = boto3.client('sns')
http = urllib3.PoolManager()

# 환경 변수 설정
ATHENA_DB = os.environ.get('ATHENA_DB', 'athena_cloudtrail_db')
ATHENA_TABLE = os.environ.get('ATHENA_TABLE', 'cloudtrail_table')
WORKGROUP = os.environ.get('WORKGROUP', 'primary')
OUTPUT = os.environ.get('ATHENA_OUTPUT', 's3://s3-cloudtrail-logbucket/athena-results/')
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
DISCORD_WEBHOOK = os.environ['DISCORD_WEBHOOK']

def lambda_handler(event, context):
    # Athena 쿼리: 최근 30분 + 야간 시간대 + CreateUser/DeleteAccessKey 탐지
    query = f"""
    SELECT
      r.eventTime,
      r.eventName,
      r.userIdentity.userName AS username,
      r.sourceIPAddress
    FROM {ATHENA_DB}.{ATHENA_TABLE}
    CROSS JOIN UNNEST(records) AS t(r)
    WHERE
      (
        r.eventName LIKE '%ConsoleLogin%'
        OR r.eventName LIKE '%CreateAccessKey%'
        OR r.eventName LIKE '%CreateUser%'
        OR r.eventName LIKE '%DeleteAccessKey%'
      )
      AND from_iso8601_timestamp(r.eventTime) >= current_timestamp - interval '30' minute
      AND (
        hour(from_iso8601_timestamp(r.eventTime) + interval '9' hour) >= 22
        OR hour(from_iso8601_timestamp(r.eventTime) + interval '9' hour) < 7
      )
    ORDER BY from_iso8601_timestamp(r.eventTime) ASC
    """

    print("Athena 쿼리 실행 시작...")
    try:
        # Athena 쿼리 실행
        response = athena.start_query_execution(
            QueryString=query,
            QueryExecutionContext={'Database': ATHENA_DB},
            ResultConfiguration={'OutputLocation': OUTPUT},
            WorkGroup=WORKGROUP
        )
        query_execution_id = response['QueryExecutionId']

        # Athena 쿼리 완료 대기
        while True:
            result = athena.get_query_execution(QueryExecutionId=query_execution_id)
            status = result['QueryExecution']['Status']['State']
            if status in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
                break
            time.sleep(1)

        if status != 'SUCCEEDED':
            reason = result['QueryExecution']['Status'].get('StateChangeReason', 'No reason provided')
            print(f"Athena query failed. Reason: {reason}")
            return

        print("Athena 쿼리 성공!")

        # 쿼리 결과 가져오기
        result_set = athena.get_query_results(QueryExecutionId=query_execution_id)
        rows = result_set['ResultSet']['Rows'][1:]  # 첫 줄(헤더) 제외
        if not rows:
            print("30분 내 비정상 API 호출 없음.")
            return

        # 메시지 포맷팅
        bold_title = "**[ CloudTrail 비정상 API 탐지 ]**"
        inner_header = "비정상 API 호출 {}건 감지 (최근 30분, 야간 시간대)\n".format(len(rows))
        table_header = "{:<22} {:<15} {:<20} {}\n".format("이벤트", "사용자", "IP", "시간")
        table_divider = "-" * 85 + "\n"
        table_rows = ""

        for row in rows:
            data = [col.get('VarCharValue', '') for col in row['Data']]

            # 시간 변환 (UTC → KST)
            try:
                event_time_kst = datetime.strptime(data[0], '%Y-%m-%dT%H:%M:%SZ') + timedelta(hours=9)
                time_str = event_time_kst.strftime('%Y-%m-%d %H:%M:%S')
            except:
                time_str = data[0]

            table_rows += "{:<22} {:<15} {:<20} {}\n".format(
                data[1], data[2], data[3], time_str
            )

        # 최종 메시지 (Discord 코드블럭 형태)
        discord_message = (
            f"{bold_title}\n\n"  # 제목: 표 밖에 볼드 표시
            "```text\n"
            + inner_header  # 표 안에 감지 건수 출력
            + table_header
            + table_divider
            + table_rows +
            "```"
        )

        print("알람 메시지:\n", discord_message)

        # SNS 알림 전송
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="[ALERT] 최근 30분 야간 비정상 API 호출 감지",
            Message=bold_title + "\n\n" + inner_header + table_header + table_divider + table_rows
        )
        print("SNS 알림 전송 완료")

        # Discord Webhook 알림 전송
        http.request(
            'POST',
            DISCORD_WEBHOOK,
            body=json.dumps({"content": discord_message}),
            headers={'Content-Type': 'application/json'}
        )
        print("Discord 알림 전송 완료")

    except Exception as e:
        print(f"Lambda 실행 중 오류 발생: {str(e)}")

