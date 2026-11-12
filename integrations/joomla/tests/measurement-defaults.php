<?php
namespace Joomla\CMS\Form\Field {
    class ListField {
        protected $type;
        public $form;
        public $value = 'unit';
        public function render() { return $this->getInput(); }
        protected function getInput() { return $this->value; }
    }
}
namespace {
    define('_JEXEC', 1);
    foreach (['mod_vstupenky_online'=>'VstupenkyOnline','mod_festapp_tickets'=>'FestappTickets'] as $element=>$namespace) {
        $modules = getenv('FESTAPP_JOOMLA_MODULE_ROOT') ?: __DIR__ . '/../build';
        require $modules . '/' . $element . '/src/Field/MeasurementField.php';
        $class = 'Festapp\\Module\\' . $namespace . '\\Site\\Field\\MeasurementField';
        foreach ([[0,null,'host'],[42,null,'unit'],[0,'unit','unit'],[0,'host','host']] as [$id,$submitted,$expected]) {
            $field = new $class;
            $field->value = $submitted ?? 'unit';
            $field->form = new class($id,$submitted) {
                public function __construct(private int $id, private ?string $submitted) {}
                public function getValue($name, $group = null) { return $name === 'id' ? $this->id : $this->submitted; }
            };
            if ($field->render() !== $expected) { throw new \RuntimeException('Incorrect measurement default'); }
        }
    }
    echo json_encode(['assertions'=>8, 'source'=>'installed module', 'new_modules'=>'host', 'legacy_modules'=>'unit']), "\n";
}
