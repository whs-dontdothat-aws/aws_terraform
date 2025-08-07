import boto3
import os

# EC2 클라이언트 생성
ec2 = boto3.client('ec2')

# 환경변수로 대상 EC2 인스턴스 ID 설정
TARGET_INSTANCE_ID = os.environ['TARGET_INSTANCE_ID']

def lambda_handler(event, context):
    # 이벤트에서 스냅샷 ID 추출
    snapshot_id = event.get('snapshot_id')
    if not snapshot_id:
        raise Exception("snapshot_id is required in the event payload")

    # 스냅샷 완료 상태 대기
    print(f"Waiting for snapshot {snapshot_id} to complete...")
    waiter = ec2.get_waiter('snapshot_completed')
    waiter.wait(SnapshotIds=[snapshot_id])
    print(f"Snapshot {snapshot_id} is now completed.")

    # 대상 인스턴스의 가용 영역(Availability Zone) 확인
    instance_info = ec2.describe_instances(InstanceIds=[TARGET_INSTANCE_ID])
    az = instance_info['Reservations'][0]['Instances'][0]['Placement']['AvailabilityZone']

    # 스냅샷을 기반으로 볼륨 생성
    volume_response = ec2.create_volume(
        SnapshotId=snapshot_id,
        AvailabilityZone=az,
        VolumeType='gp2',
        TagSpecifications=[
            {
                'ResourceType': 'volume',
                'Tags': [{'Key': 'Name', 'Value': f'forensic-volume-from-{snapshot_id}'}]
            }
        ]
    )

    volume_id = volume_response['VolumeId']
    print(f"Created volume {volume_id}")

    # 볼륨이 available 상태가 될 때까지 대기
    ec2.get_waiter('volume_available').wait(VolumeIds=[volume_id])

    # 생성한 볼륨을 대상 인스턴스에 /dev/sdf로 연결
    ec2.attach_volume(
        VolumeId=volume_id,
        InstanceId=TARGET_INSTANCE_ID,
        Device='/dev/sdf'
    )

    # 연결 결과 반환
    return {
        'attached_volume_id': volume_id,
        'target_instance_id': TARGET_INSTANCE_ID,
        'device': '/dev/sdf'
    }
