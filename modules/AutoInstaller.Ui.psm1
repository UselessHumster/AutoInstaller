Set-StrictMode -Version Latest

function Test-AIWindowsGuiAvailable {
    $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    $isWindows = if ($isWindowsVariable) { [bool]$isWindowsVariable.Value } else { $PSVersionTable.PSEdition -eq 'Desktop' }
    return $isWindows -and [Environment]::UserInteractive
}

function Start-AIWinFormsUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][object]$Logger,
        [switch]$DryRun
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "AutoInstaller - $($Profile.company)"
    $form.Width = 760
    $form.Height = 740
    $form.StartPosition = 'CenterScreen'

    $departmentLabel = [System.Windows.Forms.Label]::new()
    $departmentLabel.Text = 'Department'
    $departmentLabel.Left = 16
    $departmentLabel.Top = 18
    $departmentLabel.Width = 120
    $form.Controls.Add($departmentLabel)

    $departmentBox = [System.Windows.Forms.ComboBox]::new()
    $departmentBox.Left = 140
    $departmentBox.Top = 14
    $departmentBox.Width = 260
    $departmentBox.DropDownStyle = 'DropDownList'
    foreach ($department in @($Profile.departments)) {
        [void]$departmentBox.Items.Add($department.id)
    }
    if ($departmentBox.Items.Count -gt 0) {
        $departmentBox.SelectedIndex = 0
    }
    $form.Controls.Add($departmentBox)

    $computerNameLabel = [System.Windows.Forms.Label]::new()
    $computerNameLabel.Text = 'Computer name'
    $computerNameLabel.Left = 16
    $computerNameLabel.Top = 50
    $computerNameLabel.Width = 120
    $form.Controls.Add($computerNameLabel)

    $computerNameBox = [System.Windows.Forms.TextBox]::new()
    $computerNameBox.Left = 140
    $computerNameBox.Top = 46
    $computerNameBox.Width = 260
    $form.Controls.Add($computerNameBox)

    $dryRunCheck = [System.Windows.Forms.CheckBox]::new()
    $dryRunCheck.Text = 'Dry run'
    $dryRunCheck.Left = 420
    $dryRunCheck.Top = 16
    $dryRunCheck.Width = 120
    $dryRunCheck.Checked = [bool]$DryRun
    $form.Controls.Add($dryRunCheck)

    $taskList = [System.Windows.Forms.CheckedListBox]::new()
    $taskList.Left = 16
    $taskList.Top = 116
    $taskList.Width = 700
    $taskList.Height = 240
    $taskList.CheckOnClick = $true
    $taskList.DisplayMember = 'Name'
    $form.Controls.Add($taskList)
    $refreshTasks = {
        $taskList.Items.Clear()
        $preview = New-AIRunContext -Profile $Profile -ProfilePath $ProfilePath -DepartmentId ([string]$departmentBox.SelectedItem) -NoPrompt -DryRun
        foreach ($task in @(New-AITaskPlan -Context $preview)) {
            [void]$taskList.Items.Add($task, $true)
        }
    }
    $departmentBox.Add_SelectedIndexChanged($refreshTasks)
    & $refreshTasks

    $selectAllButton = [System.Windows.Forms.Button]::new()
    $selectAllButton.Text = 'Select all'
    $selectAllButton.Left = 16
    $selectAllButton.Top = 80
    $selectAllButton.Width = 120
    $selectAllButton.Add_Click({
        for ($index = 0; $index -lt $taskList.Items.Count; $index++) {
            $taskList.SetItemChecked($index, $true)
        }
    })
    $form.Controls.Add($selectAllButton)

    $deselectAllButton = [System.Windows.Forms.Button]::new()
    $deselectAllButton.Text = 'Deselect all'
    $deselectAllButton.Left = 148
    $deselectAllButton.Top = 80
    $deselectAllButton.Width = 120
    $deselectAllButton.Add_Click({
        for ($index = 0; $index -lt $taskList.Items.Count; $index++) {
            $taskList.SetItemChecked($index, $false)
        }
    })
    $form.Controls.Add($deselectAllButton)

    $output = [System.Windows.Forms.TextBox]::new()
    $output.Left = 16
    $output.Top = 372
    $output.Width = 700
    $output.Height = 240
    $output.Multiline = $true
    $output.ScrollBars = 'Vertical'
    $output.ReadOnly = $true
    $form.Controls.Add($output)

    $runButton = [System.Windows.Forms.Button]::new()
    $runButton.Text = 'Run'
    $runButton.Left = 16
    $runButton.Top = 628
    $runButton.Width = 120
    $form.Controls.Add($runButton)

    $closeButton = [System.Windows.Forms.Button]::new()
    $closeButton.Text = 'Close'
    $closeButton.Left = 596
    $closeButton.Top = 628
    $closeButton.Width = 120
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    $runButton.Add_Click({
        $uiLogger = $null
        try {
            $runButton.Enabled = $false
            $output.Clear()

            $uiLogger = [pscustomobject]@{
                RunDirectory = $Logger.RunDirectory
                LogFile      = $Logger.LogFile
                ReportFile   = $Logger.ReportFile
                OnLog        = {
                    param(
                        [Parameter(Mandatory)][string]$Line,
                        [string]$Level,
                        [string]$Message
                    )

                    $output.AppendText($Line + [Environment]::NewLine)
                    $output.SelectionStart = $output.TextLength
                    $output.ScrollToCaret()
                    $output.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }

            $context = New-AIRunContext -Profile $Profile -ProfilePath $ProfilePath -DepartmentId ([string]$departmentBox.SelectedItem) -ComputerName $computerNameBox.Text -NoPrompt -DryRun:$($dryRunCheck.Checked)
            $selectedIds = @($taskList.CheckedItems | ForEach-Object { $_.Id })
            $tasks = @(New-AITaskPlan -Context $context | Where-Object { $_.Id -in $selectedIds })
            if ($tasks.Count -eq 0) { throw 'Select at least one task.' }
            $departmentBox.Enabled = $false
            $taskList.Enabled = $false
            $selectAllButton.Enabled = $false
            $deselectAllButton.Enabled = $false
            $computerNameBox.Enabled = $false
            $dryRunCheck.Enabled = $false
            $closeButton.Enabled = $false
            Invoke-AITaskPlan -Context $context -Tasks $tasks -Logger $uiLogger
            Export-AIRunReport -Context $context -Tasks $tasks -Logger $uiLogger
        }
        catch {
            $errorLogger = if ($uiLogger) { $uiLogger } else { $Logger }
            Write-AILog -Logger $errorLogger -Level 'ERROR' -Message $_.Exception.Message
        }
        finally {
            $runButton.Enabled = $true
            $departmentBox.Enabled = $true
            $taskList.Enabled = $true
            $selectAllButton.Enabled = $true
            $deselectAllButton.Enabled = $true
            $computerNameBox.Enabled = $true
            $dryRunCheck.Enabled = $true
            $closeButton.Enabled = $true
        }
    })

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function Test-AIWindowsGuiAvailable, Start-AIWinFormsUi
