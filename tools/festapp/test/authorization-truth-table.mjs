// Evaluate the unchanged real predicates in one server-side loop. Expected
// rights/envelope assertions stay in JavaScript, independently of this executor.
import assert from 'node:assert/strict';

export async function truthTableRows(db, fixture, predicates) {
    assert.match(predicates, /^select /);
    const query = predicates.replace(/\$([123])\b/g, (_, index) =>
        ['f_occasion', 'f_unit', 'f_org'][Number(index) - 1]);
    assert(!query.includes('$'), 'Unexpected predicate placeholder');
    await db.query(`CREATE TEMP TABLE authorization_truth_rows (
        bits integer PRIMARY KEY, rights jsonb NOT NULL, context jsonb NOT NULL,
        original jsonb NOT NULL, actor_role text NOT NULL
    ) ON COMMIT DROP`);
    await db.query("select set_config('festapp.test.truth_fixture',$1,true)",
        [JSON.stringify(fixture)]);
    await db.query(`DO $truth$
    DECLARE
        fixture jsonb := current_setting('festapp.test.truth_fixture')::jsonb;
        f_occasion bigint := (fixture->>'occasion')::bigint;
        f_unit bigint := (fixture->>'unit')::bigint;
        f_org bigint := (fixture->>'org')::bigint;
        f_actor uuid := (fixture->>'actor')::uuid;
        context_input jsonb := jsonb_build_object('organization', f_org,
            'link', fixture->>'link', 'platform', jsonb_build_object('platform','web'));
        combination integer;
        evaluated jsonb;
        current_context jsonb;
        previous_context jsonb;
        evaluated_role text;
    BEGIN
        FOR combination IN 0..2047 LOOP
            RESET ROLE;
            UPDATE occasion_users SET
                is_editor=(combination & 1)<>0, is_editor_view=(combination & 2)<>0,
                is_editor_order=(combination & 4)<>0, is_editor_order_view=(combination & 8)<>0,
                is_manager=(combination & 16)<>0, is_receptionist=(combination & 512)<>0,
                is_approver=(combination & 1024)<>0
                WHERE occasion=f_occasion AND "user"=f_actor;
            UPDATE unit_users SET is_editor=(combination & 32)<>0,
                is_manager=(combination & 64)<>0, is_editor_view=(combination & 256)<>0
                WHERE unit=f_unit AND "user"=f_actor;
            UPDATE organization_users SET is_admin=(combination & 128)<>0
                WHERE organization=f_org AND "user"=f_actor;
            PERFORM set_config('request.jwt.claim.sub',f_actor::text,true),
                set_config('request.jwt.claim.role','authenticated',true);
            SET LOCAL ROLE authenticated;
            SELECT to_jsonb(actual) INTO evaluated FROM (${query}) actual;
            current_context := get_app_config_v218(context_input);
            previous_context := authorization_context_before_for_test(context_input);
            evaluated_role := current_user;
            RESET ROLE;
            INSERT INTO authorization_truth_rows VALUES
                (combination,evaluated,current_context,previous_context,evaluated_role);
        END LOOP;
    END $truth$`);
    const {rows} = await db.query('SELECT * FROM authorization_truth_rows ORDER BY bits');
    assert.equal(rows.length, 2048, 'Every role combination must execute');
    rows.forEach((row, bits) => {
        assert.equal(row.bits, bits, 'No missing/duplicate combination');
        assert.equal(row.actor_role, 'authenticated', 'Evaluate real rights as the client role');
    });
    return rows;
}
