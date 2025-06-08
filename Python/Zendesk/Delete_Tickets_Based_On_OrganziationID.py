import configparser
import requests
import time

# Load configuration from ini file
config = configparser.ConfigParser()
config.read('zendesk_config.ini')

api_token = config.get('Zendesk', 'api_token')
auth_email = config.get('Zendesk', 'auth_email')
rate_limit = config.get('Zendesk', 'rate_limit')
specified_string = config.get('Zendesk', 'specified_string').lower()
subdomain = config.get('Zendesk', 'subdomain')
organization_ids = config.get('Zendesk', 'organization_ids')

# Authentication
auth = (f'{auth_email}/token', api_token)

# Rate Limit Configuration
calls_per_minute = 100
delay_between_calls = 60 / calls_per_minute  # 0.6 seconds

def fetch_tickets(search_url, params):
    response = requests.get(search_url, params=params, auth=auth)
    if response.status_code != 200:
        print("Failed to fetch tickets:", response.text)
        return [], None  # Empty results and no next page
    data = response.json()
    tickets = data.get('results', [])
    next_page = data.get('next_page')
    return tickets, next_page

def delete_tickets_for_organization(organization_ids):
    # Initial search URL and parameters for finding closed tickets
    search_url = f'https://{subdomain}.zendesk.com/api/v2/search.json'
    search_params = {'query': f'type:ticket organization_ids:{organization_ids} status:closed'}

    while search_url:
        tickets, next_page = fetch_tickets(search_url, search_params)
        # Delete tickets (with rate limiting)
        for ticket in tickets:
            delete_url = f'https://{subdomain}.zendesk.com/api/v2/tickets/{ticket["id"]}.json'
            delete_response = requests.delete(delete_url, auth=auth)

            if delete_response.status_code == 204:
                print(f'Ticket {ticket["id"]} from organization {organization_ids} deleted successfully.')
            else:
                print(f'Failed to delete ticket {ticket["id"]} from organization {organization_ids}.')

            time.sleep(delay_between_calls)  # Delay to comply with rate limit

        # Prepare for the next iteration if there are more pages
        search_url = next_page
        search_params = {}  # Clear params because next_page URL contains all necessary parameters

for org_id in organization_ids:
    delete_tickets_for_organization(org_id)
