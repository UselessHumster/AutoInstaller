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
    $form.Height = 560
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

    $output = [System.Windows.Forms.TextBox]::new()
    $output.Left = 16
    $output.Top = 88
    $output.Width = 700
    $output.Height = 368
    $output.Multiline = $true
    $output.ScrollBars = 'Vertical'
    $output.ReadOnly = $true
    $form.Controls.Add($output)

    $runButton = [System.Windows.Forms.Button]::new()
    $runButton.Text = 'Run'
    $runButton.Left = 16
    $runButton.Top = 472
    $runButton.Width = 120
    $form.Controls.Add($runButton)

    $closeButton = [System.Windows.Forms.Button]::new()
    $closeButton.Text = 'Close'
    $closeButton.Left = 596
    $closeButton.Top = 472
    $closeButton.Width = 120
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    $runButton.Add_Click({
        try {
            $runButton.Enabled = $false
            $context = New-AIRunContext -Profile $Profile -ProfilePath $ProfilePath -DepartmentId ([string]$departmentBox.SelectedItem) -ComputerName $computerNameBox.Text -DryRun:$($dryRunCheck.Checked)
            $tasks = New-AITaskPlan -Context $context
            Invoke-AITaskPlan -Context $context -Tasks $tasks -Logger $Logger
            Export-AIRunReport -Context $context -Tasks $tasks -Logger $Logger
            $output.Text = ($tasks | ForEach-Object { "$($_.Status) $($_.Id) $($_.Message)" }) -join [Environment]::NewLine
        }
        catch {
            $output.Text = $_.Exception.Message
            Write-AILog -Logger $Logger -Level 'ERROR' -Message $_.Exception.Message
        }
        finally {
            $runButton.Enabled = $true
        }
    })

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function Test-AIWindowsGuiAvailable, Start-AIWinFormsUi
