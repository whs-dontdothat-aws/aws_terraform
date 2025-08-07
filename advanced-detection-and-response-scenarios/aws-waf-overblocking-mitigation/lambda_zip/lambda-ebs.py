import boto3
import json

# EC2 클라이언트 생성
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    # 이벤트에서 인스턴스 ID 추출
    instance_id = event.get('instance_id')
    if not instance_id:
        raise Exception("instance_id is required")

    # 대상 EC2 인스턴스 정보 조회
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]

    # 루트 디바이스 이름 추출 (예: /dev/xvda)
    root_device = instance['RootDeviceName']
    root_volume_id = None

    # 루트 디바이스와 일치하는 EBS 볼륨 ID 찾기
    for mapping in instance['BlockDeviceMappings']:
        if mapping['DeviceName'] == root_device:
            root_volume_id = mapping['Ebs']['VolumeId']
            break

    if not root_volume_id:
        raise Exception("Root volume not found")

    print(f"Root volume ID: {root_volume_id}")

    # 스냅샷 생성 (루트 볼륨 기준)
    snapshot_response = ec2.create_snapshot(
        VolumeId=root_volume_id,
        Description=f"Snapshot of {root_volume_id} from instance {instance_id} for forensic analysis",
        TagSpecifications=[   # 스냅샷에 태그 지정
            {
                'ResourceType': 'snapshot',
                'Tags': [
                    {'Key': 'Name', 'Value': f"{instance_id}-forensic-snapshot"},
                    {'Key': 'SourceInstance', 'Value': instance_id}
                ]
            }
        ]
    )

    snapshot_id = snapshot_response['SnapshotId']
    print(f"Created snapshot: {snapshot_id}")

    # 생성된 스냅샷 ID와 인스턴스 ID 반환
    return {
        'snapshot_id': snapshot_id,
        'instance_id': instance_id
    }