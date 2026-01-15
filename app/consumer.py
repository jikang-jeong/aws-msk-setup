import json
import time
import base64

def handler(event, context):
    for record in event['records'].values():
        for msg in record:
            # base64 디코딩 후 JSON 파싱
            value = json.loads(base64.b64decode(msg['value']).decode('utf-8'))
            print(f"Received: {value}")
            time.sleep(0.1)  # 100ms 지연 (Lag 발생용)
    
    return {'statusCode': 200}
