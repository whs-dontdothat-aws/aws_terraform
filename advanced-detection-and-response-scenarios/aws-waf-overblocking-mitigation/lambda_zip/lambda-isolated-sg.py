import boto3
import os
import json

# EC2 클라이언트 생성
ec2 = boto3.client('ec2')

# 격리용 보안 그룹 ID를 환경 변수에서 가져옴
ISOLATION_SG_ID = os.environ['ISOLATION_SG_ID']

def lambda_handler(event, context):
    # 이벤트 로그 출력
    print("Received event:", json.dumps(event))
    
    # 이벤트에서 EC2 인스턴스 ID 추출
    instance_id = event.get('instance_id')
    if not instance_id:
        raise Exception("Error: 'instance_id' is required in the event payload")

    # EC2 인스턴스에서 네트워크 인터페이스 정보 조회
    response = ec2.describe_instances(InstanceIds=[instance_id])
    network_interfaces = response['Reservations'][0]['Instances'][0]['NetworkInterfaces']

    # 각 네트워크 인터페이스에 대해 격리 보안 그룹 적용
    for ni in network_interfaces:
        eni_id = ni['NetworkInterfaceId']
        print(f"Attaching isolation security group to ENI: {eni_id}")

        # 해당 ENI에 격리용 보안 그룹 설정
        ec2.modify_network_interface_attribute(
            NetworkInterfaceId=eni_id,
            Groups=[ISOLATION_SG_ID]
        )

    # 결과 반환
    return {
        'status': 'isolated',
        'instance_id': instance_id
    }
