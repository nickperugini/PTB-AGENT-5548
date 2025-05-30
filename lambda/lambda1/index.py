import boto3, os

def handler(event, context):
    s3 = boto3.client("s3")
    dynamo = boto3.resource("dynamodb")
    bucket = os.environ["BUCKET"]
    table_name = os.environ["DYNAMO_TABLE"]

    # 1) write a simple text file to S3
    s3.put_object(
        Bucket=bucket,
        Key="lambda1.txt",
        Body="Hello from lambda1"
    )

    # 2) put an item into DynamoDB
    table = dynamo.Table(table_name)
    table.put_item(
        Item={
            "PK": "lambda1",
            "timestamp": str(context.aws_request_id)
        }
    )

    return {'statusCode': 200, 'body': 'ok'}
