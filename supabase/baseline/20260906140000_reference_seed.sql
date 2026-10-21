--
-- PostgreSQL database dump
--


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: client_sync_component_sources; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.client_sync_component_sources VALUES (1, 'occasion_config', 'public.images', 'images.occasion', '{id,link,occasion}', '{add_image_record,remove_image_records}', '{}', 'migrate', 'occasion_image_factory', false);


--
-- PostgreSQL database dump complete
--

