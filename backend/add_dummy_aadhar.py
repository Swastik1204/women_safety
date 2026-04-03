import os
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# Initialize Firebase app if it hasn't been initialized already
try:
    firebase_admin.get_app()
except ValueError:
    key_path = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')
    if os.path.exists(key_path):
        print(f"Using service account key found at: {key_path}")
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)
    else:
        print("No 'serviceAccountKey.json' found. Falling back to default credentials.")
        try:
            firebase_admin.initialize_app()
        except Exception as e:
            print("\nError: Could not initialize Firebase Admin SDK.")
            print("Please either:")
            print("1. Set the GOOGLE_APPLICATION_CREDENTIALS environment variable, OR")
            print(f"2. Download your Firebase Admin SDK service account key and save it as: {key_path}\n")
            raise e

db = firestore.client()

def add_dummy_aadhar():
    # Specific test user 1
    test_id_1 = '123456789012'
    db.collection('aadhar_ver').document(test_id_1).set({
        'First_name': 'John',
        'Last_name': 'Doe',
        'dob': '01/01/1990',
        'gender': 'Male'
    })
    print(f"Added specific test user: {test_id_1} -> John Doe (DOB: 01/01/1990, Gender: Male)")
    
    # Specific test user 2 (Ayush Srivastava)
    test_id_2 = '987424834182'
    db.collection('aadhar_ver').document(test_id_2).set({
        'First_name': 'Ayush',
        'Last_name': 'Srivastava',
        'dob': "25/04/2004",
        'gender': 'Male'
    })
    print(f"Added specific test user: {test_id_2} -> Ayush Srivastava (DOB: 25/04/2004, Gender: Male)")

if __name__ == '__main__':
    add_dummy_aadhar()
