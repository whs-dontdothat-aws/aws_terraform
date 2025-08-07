import boto3
import os
import json

ssm = boto3.client('ssm')

# 분석용 EC2 인스턴스 ID는 환경변수로 전달
TARGET_INSTANCE_ID = os.environ['TARGET_INSTANCE_ID']

def lambda_handler(event, context):
    device_name = event.get('device', '/dev/sdf')  # 기본값 /dev/sdf
    mount_point = "/mnt/forensic"

    commands = [
        f"sudo mkdir -p {mount_point}",
        f"sudo mount {device_name} {mount_point}",

        # 시스템 로그 수집
        f"sudo cat {mount_point}/var/log/syslog > /tmp/syslog_copy.txt || echo 'No syslog'",
        f"sudo cat {mount_point}/var/log/messages > /tmp/messages_copy.txt || echo 'No messages'",

        # 사용자 및 권한 관련 정보
        f"sudo cat {mount_point}/etc/passwd > /tmp/passwd_copy.txt || echo 'No passwd'",
        f"sudo cat {mount_point}/etc/shadow > /tmp/shadow_copy.txt || echo 'No shadow'",
        f"sudo cat {mount_point}/etc/group > /tmp/group_copy.txt || echo 'No group'",

        # 셸 히스토리
        f"sudo cat {mount_point}/root/.bash_history > /tmp/root_bash_history.txt || echo 'No root bash history'",
        f"sudo find {mount_point}/home -name '.bash_history' -exec cat {{}} \\; > /tmp/user_bash_histories.txt || echo 'No user bash histories'",

        # SSH 백도어 흔적 확인
        f"sudo find {mount_point}/home -name 'authorized_keys' -exec cat {{}} \\; > /tmp/ssh_keys.txt || echo 'No authorized_keys'",
        f"sudo find {mount_point}/root -name 'authorized_keys' -exec cat {{}} \\; >> /tmp/ssh_keys.txt || echo 'No root ssh keys'",

        # 임시 디렉토리 내용 확인
        f"sudo ls -alhR {mount_point}/tmp > /tmp/tmp_dir_listing.txt || echo 'No /tmp dir'",
        f"sudo ls -alhR {mount_point}/var/tmp > /tmp/var_tmp_dir_listing.txt || echo 'No /var/tmp dir'",

        # 실행파일 해시 수집
        f"sudo sha256sum {mount_point}/bin/* > /tmp/bin_hashes.txt || echo 'No bin files'",
        f"sudo sha256sum {mount_point}/usr/bin/* > /tmp/usr_bin_hashes.txt || echo 'No usr/bin files'",

        # 네트워크 설정
        f"sudo cat {mount_point}/etc/hosts > /tmp/hosts.txt || echo 'No hosts'",
        f"sudo cat {mount_point}/etc/resolv.conf > /tmp/resolv_conf.txt || echo 'No resolv.conf'",
        f"sudo cat {mount_point}/etc/hostname > /tmp/hostname.txt || echo 'No hostname'",

        # 마운트 해제
        f"sudo umount {mount_point}"
    ]

    # SSM 명령 실행
    response = ssm.send_command(
        InstanceIds=[TARGET_INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={
            "commands": commands
        },
        TimeoutSeconds=180,
    )

    command_id = response['Command']['CommandId']
    print(f"SSM command sent. Command ID: {command_id}")

    return {
        "command_id": command_id,
        "target_instance_id": TARGET_INSTANCE_ID
    }
