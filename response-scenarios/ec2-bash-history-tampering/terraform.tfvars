# 사용할 AWS 리전 설정
aws_region         = "ap-northeast-2"

# EC2 인스턴스 타입을 설정 (무료 티어에 해당하는 기본적인 사양은 아래와 같음)
ec2_instance_type  = "t2.micro"

# 알림을 받을 디스코드 Webhook URL로 설정
# 해당 URL을 통해 Lambda 함수가 알림을 디스코드 채널로 전송
discord_webhook_url = "https://discord.com/api/webhooks/1384738826991304757/EuWFbY7ZxoX7eSNp_CCYWzptz0qN5rIrRkTnwdCFclxH1Pl_d5V-7WqEXqOpn8yg6I0P"

# 알림을 받을 이메일 주소로 설정
# 보안 이벤트가 발생 시 SNS를 통해 해당 이메일로 알람 전송
sns_email          = "hyungeunson@naver.com"