import requests
import time

# Authentication and headers
SUBDOMAIN = 'observian'
EMAIL = 'paul.kell@observian.com'
TOKEN = '1fW487XBDZpE4vN3B048B7knCfpt5UXE3LMjj5ZF'
AUTH = (EMAIL + '/token', TOKEN)
HEADERS = {'Content-Type': 'application/json'}

# Rate limiting parameters
MAX_CALLS_PER_MINUTE = 95
SLEEP_TIME = 60 / MAX_CALLS_PER_MINUTE  # Pause between API calls to respect the rate limit

def find_and_delete_tickets(search_string):
    page = 1
    tickets_deleted = 0

    while True:
        search_url = f"https://{SUBDOMAIN}.zendesk.com/api/v2/search.json?query=type:ticket status:closed subject:\"{search_string}\""
        response = requests.get(search_url, auth=AUTH, headers=HEADERS, params={'page': page})

        if response.status_code != 200:
            print(f"Error fetching tickets: {response.status_code}")
            break

        tickets = response.json()['results']
        if not tickets:
            break  # No more tickets to process

        for ticket in tickets:
            delete_url = f"https://{SUBDOMAIN}.zendesk.com/api/v2/tickets/{ticket['id']}.json"
            delete_response = requests.delete(delete_url, auth=AUTH, headers=HEADERS)
            if delete_response.status_code == 204:
                print(f"Deleted ticket ID: {ticket['id']}")
                tickets_deleted += 1
            else:
                print(f"Error deleting ticket ID: {ticket['id']}: {delete_response.status_code}")

            time.sleep(SLEEP_TIME)  # Respect the rate limit

        page += 1

    print(f"Total tickets deleted: {tickets_deleted}")

search_string = "CVE-2022-48566"
find_and_delete_tickets(search_string)
