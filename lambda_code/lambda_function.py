import logging
from os import environ
from time import sleep
from functools import wraps
from datetime import date, timedelta, datetime
from boto3 import Session
from botocore.exceptions import ClientError, PaginationError


s3_prefix = environ['S3_BASE_PREFIX']
last_copy_param_name = environ['LAST_COPY_PARAM_NAME']
source_bucket_name = environ['SOURCE_BUCKET']
target_bucket_name = environ['TARGET_BUCKET']
copy_logs_role_arn = environ['COPY_LOGS_ROLE_ARN']
module_name = environ['MODULE_NAME']

logger = logging.getLogger()
if logger.handlers:
    for handler in logger.handlers:
        logger.removeHandler(handler)
logger.setLevel(environ['LOGGING_LEVEL'])
logging.basicConfig(format='[%(asctime)s] (%(lineno)s) %(funcName)s  %(levelname)s: %(message)s')


# Both error codes are used on different AWS API's, meaning the same
LIMIT_ERRORS = ['LimitExceededException', 'ClientLimitExceededException', 'TooManyRequestsException']

def exception_handler(original_function, number_of_tries=4, delay=3):
    """
    Provide an exception handler with exponential backoff for AWS API calls
    """
    @wraps(original_function)
    def retried_function(*args, **kwargs):
        for i in range(number_of_tries):
            try:
                return original_function(*args, **kwargs)
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code in LIMIT_ERRORS:
                    backoff = delay * (2**i)
                    sleep(backoff)
                else:
                    logger.error(e)
                    raise
            except PaginationError as e:
                logger.error(e)
                raise
    return retried_function

@exception_handler
def assume_role(boto_session: object, role_arn: str, duration: int, session_name=module_name) -> dict:

    output = {
        'Success': None,
        'Credentials': None,
        'Error': None
    }

    sts_client = boto_session.client('sts')
    assume_role_object = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name,
        DurationSeconds=duration
    )
    logger.info('AssumeRole succeeded for %s' % role_arn)
    output['Credentials'] = assume_role_object['Credentials']
    output['Success'] = True
    return output

class ParamStore(object):
    @exception_handler
    def __init__(self, boto_session: object) -> None:
        self.client = boto_session.client('ssm')

    @exception_handler
    def get_ssm_param(self, ssm_param_name: str) -> dict:
        ssm_param = self.client.get_parameter(Name=ssm_param_name, WithDecryption=True)['Parameter']['Value']
        logger.info('SSM param value for %s is %s', ssm_param_name, ssm_param)
        return ssm_param
    
    @exception_handler
    def set_ssm_param(self, ssm_param_name: str, value: str, type='String') -> dict:
        ssm_param = self.client.put_parameter(
            Name=ssm_param_name, 
            Value=value, 
            Type=type, 
            Overwrite=True
            )
        logger.info('SSM param %s was successfully updated', ssm_param_name)
        return ssm_param['Version']


class ObjectStore(object):
    @exception_handler
    def __init__(self, boto_session: object, bucket: str, ) -> None:
        self.bucket = bucket
        self.client = boto_session.client('s3')

    @exception_handler
    def list_objects_by_prefix(self, prefix: str, delimiter: str) -> list:
        paginator = self.client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=self.bucket, Prefix=prefix, Delimiter=delimiter)
        objects_list = []

        for page in pages:

            for object in page['Contents']:
                if object['Key'] == prefix:
                    pass
                else:
                    objects_list.append(
                        {
                            'Key': object['Key'],
                            'Size': object['Size'],
                            'StorageClass': object['StorageClass']
                        }
                    )
        logger.debug('S3 objects list for prefix %s: %s', prefix, str(objects_list))
        logger.info('%d S3 objects are present in prefix %s', len(objects_list), prefix)
        return objects_list
    
    @exception_handler
    def copy_objects(self, destination_bucket: str, prefix='', delimiter='/') -> None:
        s3_objects = self.list_objects_by_prefix(prefix, delimiter)
        for s3_object in s3_objects:
            copy_source = '/'.join([self.bucket, s3_object['Key']])
            self.client.copy_object(
                CopySource=copy_source, 
                Bucket=destination_bucket, 
                Key=s3_object['Key'],
                ServerSideEncryption='aws:kms',
                BucketKeyEnabled=True
                )
        else:
            logger.info('S3 prefix used: %s', prefix)
            logger.info('S3 objects copied from %s to %s', self.bucket, destination_bucket )


def lambda_handler(event: dict, context: dict):
    logger.debug('Lambda function triggered with event: %s', str(event))
    
    logger.info('Initializing boto session with Lambda IAM Role')
    lambda_role_session = Session()

    ssm = ParamStore(lambda_role_session)
    date_format = '%Y/%m/%d'
    start_date = datetime.strptime(str(ssm.get_ssm_param(last_copy_param_name)), date_format) + timedelta(1)
    end_date = datetime.today()
    days = [start_date + timedelta(i) for i in range((end_date - start_date).days)]
    
    logger.info('Initializing boto session with Copy Logs IAM Role')
    copy_logs_role_credentials = assume_role(lambda_role_session, copy_logs_role_arn, 3600)['Credentials']
    copy_logs_role_session = Session(
        aws_access_key_id = copy_logs_role_credentials['AccessKeyId'],
        aws_secret_access_key = copy_logs_role_credentials['SecretAccessKey'],
        aws_session_token = copy_logs_role_credentials['SessionToken']
    )

    source_bucket = ObjectStore(copy_logs_role_session, source_bucket_name)
    for day in days:
        prefix = ''.join([s3_prefix, datetime.strftime(day, date_format), '/'])
        source_bucket.copy_objects(target_bucket_name, prefix)
    else:
        ssm.set_ssm_param(last_copy_param_name, datetime.strftime(days[-1], date_format))