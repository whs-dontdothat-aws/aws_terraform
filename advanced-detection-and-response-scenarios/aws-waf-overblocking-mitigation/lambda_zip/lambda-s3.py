import boto3
import os
import json

ssm = boto3.client('ssm')

TARGET_INSTANCE_ID = os.environ['TARGET_INSTANCE_ID']
S3_BUCKET = os.environ['S3_BUCKET_NAME']
S3_PREFIX = 'forensic-results'

def lambda_handler(event, context):
    # 업로드 대상 파일 목록
    files = [
        "syslog_copy.txt", "messages_copy.txt", "passwd_copy.txt", "shadow_copy.txt",
        "group_copy.txt", "root_bash_history.txt", "user_bash_histories.txt",
        "ssh_keys.txt", "tmp_dir_listing.txt", "var_tmp_dir_listing.txt",
        "bin_hashes.txt", "usr_bin_hashes.txt", "hosts.txt", "resolv_conf.txt",
        "hostname.txt"
    ]

    # S3 복사 명령어 리스트
    commands = [
        f"aws s3 cp /tmp/{file} s3://{S3_BUCKET}/{S3_PREFIX}/{file} || echo 'No {file}'"
        for file in files
    ]

    # SSM 명령 실행 (분석용 EC2에서 S3로 직접 업로드)
    response = ssm.send_command(
        InstanceIds=[TARGET_INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=120
    )

    command_id = response['Command']['CommandId']
    print(f"S3 upload command sent. Command ID: {command_id}")

    return {
        "s3_upload_command_id": command_id,
        "s3_bucket": S3_BUCKET,
        "s3_key_prefix": S3_PREFIX
    }
