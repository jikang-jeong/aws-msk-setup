import json
import os
from kafka import KafkaProducer

def handler(event, context):
    producer = KafkaProducer(
        bootstrap_servers=os.environ['BOOTSTRAP_SERVERS'].split(','),
        security_protocol='SSL',
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )
    
    body = json.loads(event.get('body', '{}'))
    topic = os.environ.get('TOPIC', 'test-topic')
    count = body.get('count', 1)  # 기본 1개, 지정 가능
    
    for i in range(count):
        producer.send(topic, value={'index': i, 'data': body.get('data', 'test')})
    
    producer.flush()
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'Published {count} messages', 'topic': topic})
    }
