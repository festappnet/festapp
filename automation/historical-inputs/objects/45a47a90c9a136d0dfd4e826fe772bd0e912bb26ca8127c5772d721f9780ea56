CREATE OR REPLACE FUNCTION get_is_event_allowed(ev bigint) RETURNS bool
    LANGUAGE "plpgsql" STABLE
    SECURITY DEFINER
SET search_path = public, extensions
    AS $$
    DECLARE
        userRole bigint;
        eventRoles bigint[];
    BEGIN
        eventRoles := ARRAY(select
          role
          from
            event_roles
          where
            event_roles.event = ev);

        IF coalesce(cardinality(eventRoles), 0) = 0 THEN
            RETURN true;
        END IF;

        select
          role
        into userRole
        from
          occasion_users
        where
          "user" = auth.uid() and
          occasion = (select occasion from events where events.id = ev);

        IF userRole IS NULL THEN
            RETURN false;
        END IF;
        RETURN (SELECT userRole = ANY(eventRoles));
    END;
$$;