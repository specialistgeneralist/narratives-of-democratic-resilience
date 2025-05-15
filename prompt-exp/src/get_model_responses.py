import json
import csv
import re
import sys

# Function to parse the JSON file
def parse_conversation_json(file_path):
    with open(file_path, 'r') as file:
        data = json.load(file)
    return data

# Function to extract response and justification from text
def extract_response_and_justification(text):
    # Different models format their responses differently, so we need to handle various patterns
    
    # Pattern 1: "Answer: strong yes\n\nJustification: text"
    pattern1 = re.search(r'(?:Answer:|answer:)\s*(strong yes|weak yes|unsure|weak no|strong no).*?(?:Justification:|justification:)\s*(.+?)(?:\n\n|$)', text, re.DOTALL | re.IGNORECASE)
    if pattern1:
        return pattern1.group(1).strip(), pattern1.group(2).strip()
    
    # Pattern 2: "strong yes\n\nJustification: text"
    pattern2 = re.search(r'(strong yes|weak yes|unsure|weak no|strong no).*?(?:Justification:|justification:)\s*(.+?)(?:\n\n|$)', text, re.DOTALL | re.IGNORECASE)
    if pattern2:
        return pattern2.group(1).strip(), pattern2.group(2).strip()
    
    # Pattern 3: "strong yes, justification text"
    pattern3 = re.search(r'(strong yes|weak yes|unsure|weak no|strong no),\s*(.+?)(?:\n|$)', text, re.DOTALL)
    if pattern3:
        return pattern3.group(1).strip(), pattern3.group(2).strip()
    
    # If no pattern matches, try to extract just the response
    response_match = re.search(r'(strong yes|weak yes|unsure|weak no|strong no)', text, re.IGNORECASE)
    if response_match:
        # Try to get the rest of the text as justification
        response = response_match.group(1).strip()
        # Get text after the response as justification
        justification_text = text[text.lower().find(response.lower()) + len(response):].strip()
        # Remove any leading punctuation
        justification_text = re.sub(r'^[,:\s]+', '', justification_text).strip()
        return response, justification_text
    
    # If nothing matches, return empty strings
    return "", ""

# Main function to process the file and create CSV
def create_model_responses_csv(json_file_path, csv_file_path):
    # Parse the JSON file
    conversation_data = parse_conversation_json(json_file_path)
    
    # Find the response with ensemble data
    ensemble_data = None
    for message in conversation_data:
        if message.get('type') == 'response' and 'sidecars' in message and 'ensemble' in message['sidecars']:
            ensemble_data = message['sidecars']['ensemble']
            break
    
    if not ensemble_data or 'modelOutputs' not in ensemble_data:
        print("No ensemble data found in the conversation.")
        return
    
    # Extract model responses
    model_responses = []
    for model_output in ensemble_data['modelOutputs']:
        model_name = model_output.get('model', '')
        # Get the display name from the nickname if available
        display_name = model_output.get('message', {}).get('origin', {}).get('nickname', model_name)
        
        # Get the response text
        response_text = model_output.get('message', {}).get('chain', [{}])[0].get('text', '')
        
        # Extract response and justification
        response, justification = extract_response_and_justification(response_text)
        
        model_responses.append({
            'model': display_name,
            'response': response,
            'justification': justification
        })
    
    # Write to CSV
    with open(csv_file_path, 'w', newline='') as csvfile:
        fieldnames = ['model', 'response', 'justification']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        writer.writeheader()
        for model_response in model_responses:
            writer.writerow(model_response)
    
    print(f"CSV file created successfully at {csv_file_path}")


# run
json_file_path = sys.argv[1]
csv_outfile_path = json_file_path.replace('.json', '_model_responses.csv')
create_model_responses_csv(json_file_path, csv_outfile_path)
