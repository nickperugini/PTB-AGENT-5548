import boto3, os

def handler(event, context):
    s3 = boto3.client("s3")
    bucket = os.environ["BUCKET"]
    # write a simple text file naming this Lambda
    s3.put_object(
        Bucket=bucket,
        Key="lambda2.txt",       # change per function
        Body="Hello from lambda1"  # change per function
    )
    return {"statusCode": 200, "body": "ok"}
