import urllib3       # HTTP 요청을 전송하기 위한 urllib3 모듈 임포트
import boto3         # AWS 서비스(S3 등)와 상호작용하기 위한 boto3 모듈 임포트

# 악성 IP 리스트를 저장할 S3 버킷 이름과 오브젝트 키 정의
S3_BUCKET = "s3-ip-list-bucket-tf"                      # 저장 대상 S3 버킷 이름
S3_KEY = "threat/malicious-ip-list.txt"                # S3 객체(파일)의 키 (경로 및 파일명)

# FireHOL에서 제공하는 IP 블랙리스트의 URL
FIREHOL_URL = "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset"

# AWS Lambda 핸들러 함수: 이벤트 발생 시 Lambda가 실행하는 함수
def lambda_handler(event, context):
    # HTTP 연결을 위한 PoolManager 객체 생성
    http = urllib3.PoolManager()
    
    # 블랙리스트 IP 데이터를 FireHOL 원격 URL에서 GET 방식으로 가져옴
    response = http.request('GET', FIREHOL_URL)

    # 바이너리 데이터를 UTF-8 문자열로 디코딩
    ip_list = response.data.decode('utf-8')

    # 줄 단위로 나눈 후, 공백 줄이나 주석(#)이 있는 줄은 제외한 실제 IP만 필터링함
    lines = [line for line in ip_list.split('\n') if line and not line.startswith('#')]

    # 필터링된 IP 리스트를 줄바꿈으로 연결하여 하나의 문자열로 만듦
    result = '\n'.join(lines)

    # S3 클라이언트 생성
    s3 = boto3.client('s3')

    try:
        # S3에 IP 리스트 업로드 (text 파일로 저장)
        response = s3.put_object(
            Bucket=S3_BUCKET,     # 대상 S3 버킷명
            Key=S3_KEY,           # 대상 객체 키
            Body=result,          # 파일 내용: 필터링된 IP 문자열
            ContentType='text/plain'  # 콘텐츠 타입 지정
        )
        # 업로드 성공 로그 출력
        print("Upload successful:", response)

    except Exception as e:
        # 업로드 실패 시 예외 메시지 출력 후 예외 발생시킴
        print("Upload failed:", str(e))
        raise

    # Lambda 함수의 실행 결과 반환
    return {
        'statusCode': 200,  # HTTP 상태 코드
        'body': f'Uploaded {len(lines)} IPs to s3://{S3_BUCKET}/{S3_KEY}'  # 업로드 완료 메시지
    }

