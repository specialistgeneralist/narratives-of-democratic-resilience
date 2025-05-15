function filter_asylum(JSON_INFILE, MIN_TEXT_LENGTH, MAX_TEXT_LENGTH)

%% Filter JSON infile to assert:
% 
%  (1) that short or long fields, below MIN_TEXT_LENGTH or above MAX_TEXT_LENGTH, are dropped
%

% Ingest JSON file :: convert to table
c = fileread(JSON_INFILE);
s = jsondecode(c);
% .. accommodate legacy and new file format
if isfield(s, 'data')
    s = s.data;
end
t = struct2table(s);
n0 = height(t);
fprintf(' --> Filtering %d entries in %s\n', n0, JSON_INFILE);

% -- (1) Drop rows with short or very long text fields
t.text_length = cellfun(@length, t.text);
t(t.text_length < MIN_TEXT_LENGTH | t.text_length > MAX_TEXT_LENGTH, :) = [];
fprintf(' --> Dropped %d entries in %s due to char lengths, now %d entries.\n', n0-height(t), JSON_INFILE, height(t));


% output with new outfile name
if MIN_TEXT_LENGTH > 0
    outfile = replace(JSON_INFILE, '.json', sprintf('_filtered_chars%dto%d.json', MIN_TEXT_LENGTH, MAX_TEXT_LENGTH));
else
    outfile = replace(JSON_INFILE, '.json', '_filtered.json');
end
s = table2struct(t);
c = jsonencode(s);
fid = fopen(outfile, 'w');
fwrite(fid, c);
fclose(fid);

fprintf(' --> wrote %s (%d rows).\n', outfile, height(t));

end
