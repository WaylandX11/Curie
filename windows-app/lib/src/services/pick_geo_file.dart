import 'dart:io';

/// Системный выбор `.dat` на Windows без federated-плагина: обычный диалог
/// Win32 через Windows PowerShell. Возвращает null, если пользователь отменил.
Future<String?> pickDatFilePath() async {
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Geo database (*.dat)|*.dat'
$dialog.Title = 'Choose geo database'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.FileName
}
''';
  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) return null;
    final path = result.stdout.toString().trim();
    return path.isEmpty ? null : path;
  } on Object catch (_) {
    return null;
  }
}
