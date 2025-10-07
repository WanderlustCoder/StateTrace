from pathlib import Path
text = Path("Modules/ParserPersistenceModule.psm1").read_text(newline='')
start = text.find('function Invoke-InterfaceBulkInsertInternal')
end = text.find('function Invoke-DeviceSummaryParameterized')
block = text[start:end]
idx = block.find('$providerName')
print(idx)
print(block[idx-40:idx+200])
