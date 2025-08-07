import os  # 운영체제 환경 변수 등을 사용하기 위한 os 모듈 임포트
import json  # JSON 데이터 처리를 위한 json 모듈 임포트
import boto3  # AWS 서비스와 상호작용하기 위한 boto3 라이브러리 임포트
import urllib3  # HTTP 요청을 보내기 위한 urllib3 라이브러리 임포트
from datetime import datetime, timezone, timedelta  # 날짜 및 시간 처리를 위한 datetime 관련 모듈 임포트

http = urllib3.PoolManager()  # HTTP 연결을 관리하는 PoolManager 객체 생성
WEBHOOK = os.environ["DISCORD_WEBHOOK_URL"]  # 환경 변수에서 Discord Webhook URL을 불러옴

def send_discord_message(content):
    http.request(
        "POST", WEBHOOK,  # Discord Webhook URL로 POST 요청 전송
        body=json.dumps({"content": content}).encode(),  # 메시지 내용을 JSON 형태로 인코딩하여 전송
        headers={"Content-Type": "application/json"}  # Content-Type 헤더를 JSON으로 지정
    )

def lambda_handler(event, context):
    # 이벤트 정보 파싱
    region = event.get("region", "Unknown")  # 이벤트에서 region 정보를 가져오고 없으면 'Unknown' 사용
    account = event.get("account", "Unknown")  # 이벤트에서 account 정보를 가져오고 없으면 'Unknown' 사용
    time = event.get("time", "Unknown")  # 이벤트에서 time 정보를 가져오고 없으면 'Unknown' 사용
    detail = event.get("detail", {})  # 이벤트에서 detail 정보를 가져오고 없으면 빈 딕셔너리 사용
    finding_type = detail.get("type", "Unknown")  # 탐지 유형 정보 파싱
    severity = detail.get("severity", "N/A")  # 심각도 정보 파싱
    title = detail.get("title", "No Title")  # 제목 정보 파싱
    description = detail.get("description", "No Description")  # 설명 정보 파싱
    time_utc = event.get("time", None)  # UTC 기준 시간 정보 파싱
    if time_utc:
        try:
            utc_dt = datetime.strptime(time_utc, "%Y-%m-%dT%H:%M:%SZ")  # 문자열을 datetime 객체로 변환
            kst_dt = utc_dt.astimezone(timezone(timedelta(hours=9)))  # KST(UTC+9)로 시간대 변환
            time = kst_dt.strftime("%Y-%m-%d %H:%M:%S (KST)")  # KST 기준 포맷으로 문자열 변환
        except Exception:
            time = time_utc  # 변환 실패 시 원래 값을 사용
    resource = detail.get("resource", {})  # 리소스 정보 파싱
    resource_type = resource.get("resourceType", "Unknown")  # 리소스 유형 파싱
    instance_id = resource.get("instanceDetails", {}).get("instanceId", "N/A")  # 인스턴스 ID 파싱
    src_ip = "N/A"  # 공격 IP 기본값 설정
    try:
        src_ip = detail["service"]["action"]["remoteIpDetails"]["ipAddressV4"]  # 공격 원본 IP 파싱
    except Exception:
        pass  # 값이 없거나 오류가 나면 기본값 유지

    # 1. EC2 스냅샷 생성 및 인스턴스 중단
    snapshot_ids = []  # 생성된 스냅샷 ID를 저장할 리스트
    ec2_result_msg = ""  # EC2 조치 결과 메시지
    if instance_id != "N/A":
        ec2 = boto3.client('ec2')  # EC2 클라이언트 객체 생성
        try:
            volumes = ec2.describe_volumes(
                Filters=[{'Name': 'attachment.instance-id', 'Values': [instance_id]}]
            )['Volumes']  # 해당 인스턴스에 연결된 볼륨 목록 조회
            for volume in volumes:
                volume_id = volume['VolumeId']  # 볼륨 ID 추출
                response = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=f"GuardDuty auto snapshot for {instance_id} ({volume_id})"
                )  # 볼륨의 스냅샷 생성
                snapshot_ids.append(response['SnapshotId'])  # 생성된 스냅샷 ID 저장
            ec2.stop_instances(InstanceIds=[instance_id])  # 인스턴스 중단
            ec2_result_msg = (
                f"\n\n**EC2 조치 결과**\n"
                f"- 인스턴스: `{instance_id}`\n"
                f"- 스냅샷: {', '.join(snapshot_ids) if snapshot_ids else '없음'}\n"
                f"- 조치: EBS 스냅샷 촬영 및 인스턴스 중단 완료"
            )  # 조치 결과 메시지 생성
        except Exception as e:
            ec2_result_msg = f"\n\n EC2 조치 중 오류 발생: {str(e)}"  # 오류 발생 시 메시지 저장

    # 2. Discord 메시지 전송
    content = (
        "**[ GuardDuty 탐지 알림 ]**\n"
        f"**•Type:** `{finding_type}`\n"
        f"**•Title:** {title}\n"
        f"**•설명:** {description}\n"
        f"**•심각도:** {severity}\n"
        f"**•리전:** {region}\n"
        f"**•계정:** {account}\n"
        f"**•리소스:** {resource_type} / {instance_id}\n"
        f"**•공격 IP:** {src_ip}\n"
        f"**•탐지 시각:** {time}"
        f"{ec2_result_msg}"
    )  # Discord로 전송할 메시지 내용 구성
    send_discord_message(content)  # Discord로 메시지 전송

    return {
        'statusCode': 200,
        'body': f'Snapshots: {snapshot_ids}, Instance stopped: {instance_id}'
    }  # Lambda 함수의 응답 반환
