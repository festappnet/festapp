"""Explicit selected-set contracts; historical sets are never relabelled."""


def validate_artifacts(manifest):
    common = {'postgres.dump.age', 'globals.sql.age', 'runtime.tar.age'}
    version = manifest['version']
    if version == 1:
        required = common | {'storage.tar.age'}
        allowed = required | {'r2-images.tar.age'}
    elif version == 2:
        assert manifest['format'] == 'festapp-assets'
        required = allowed = common | {'r2-images.tar.age'}
        assert manifest['storage_extended_attributes'] is False
    else:
        raise ValueError('unsupported_backup_format')
    assert required <= set(manifest['artifacts']) <= allowed, 'backup artifact format mismatch'
    assert manifest['encrypted'] is True
    assert manifest['consistency'] == 'online-operational-backup-not-promotion-rpo0'
    assert manifest['source_host'] == 'festapp-supabase-rehearsal-01'
    assert manifest['source_database'] == 'festapp_rehearsal_20260909220601'
    return version
