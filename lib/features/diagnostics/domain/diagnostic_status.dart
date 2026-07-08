/// Health of a single subsystem in the developer diagnostics view.
enum DiagnosticStatus {
  ok('Operational'),
  degraded('Degraded'),
  down('Down'),
  disabled('Disabled'),
  unknown('Unknown');

  const DiagnosticStatus(this.label);

  final String label;
}
