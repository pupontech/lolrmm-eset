#requires -Version 5.1
# CI-only regression for the production missing-process mock; never shipped in the owner kit.
$ErrorActionPreference = 'Stop'
# Export-Configuration treats @(Get-Process ...).Count -gt 0 as evidence that ecmd
# still runs. A real missing process emits no pipeline output; the fixture mock must
# do the same. Each mock is defined in an isolated scope so the real Get-Process is
# never shadowed outside this file.
$missingProcessElementCount = @( & { function Get-Process { <# no value: missing process #> }; Get-Process } ).Count
if ($missingProcessElementCount -ne 0) { throw 'Mocked missing process emitted a pipeline element; the production preflight would wrongly detect a running ecmd process and fail before the UAC boundary.' }
$nullReturnElementCount = @( & { function Get-Process { return $null }; Get-Process } ).Count
if ($nullReturnElementCount -ne 1) { throw 'Unexpected: returning $null must emit exactly one pipeline element, which is why the previous mock was defective.' }
Write-Output 'MISSING-PROCESS-MOCK-REGRESSION-PASS: missing-process mock emits zero pipeline elements; null-returning mock emits one.'
