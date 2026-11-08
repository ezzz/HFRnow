"""REST flag buckets (`topics/{participated,read,favorites}`, logged in): aliased by position, cut to a few items.

Synthetic JSON only. Each position is checked on both layers on its own:
- the anonymizer replaces the real value there and its output passes `verify_rest_buckets`;
- the independent verifier reports that position when only its real value is put back in the aliased answer.
"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

API = "https://forum.hardware.fr/api/forums/hardwarefr/"
TOPIC, CAT, SUB, COUNT = 424242, 33, 4444, 23456
TITLE, DATE, POS, READ_ID = "Secret Title Qzwx", "2031-02-03 04:05", 31337, 5551234
AUTHOR_ID, LAST_ID = "774411", "119911"


def link(kind, href, **extra):
    d = {"linked_type": kind, "type": "link", "href": href}
    d.update(extra)
    return d


def item(i=0, cat=CAT, sub=SUB):
    t = TOPIC + i
    base = "%scategories/%d/" % (API, cat)
    return {
        "id": t, "title": TITLE + str(i), "last_post_date": DATE, "is_closed": False, "is_sticky": False,
        "links": {
            "forum": link("forum", API),
            "category": link("forum_category", base),
            "subcategory": link("forum_subcategory", "%ssubcategories/%d/" % (base, sub)),
            "posts": link("list", "%ssubcategories/%d/topics/%d/posts/?page=427&results_per_page=40" % (base, sub, t),
                          count=COUNT),
            "last_author": link("user", None, title="Pseudoa Realone", tns3="mesdiscussions-%s.jpg" % LAST_ID),
            "author": link("user", None, title="Pseudob Realtwo", tns3="mesdiscussions-%s.png" % AUTHOR_ID)},
        "type": "topic", "href": "%ssubcategories/%d/topics/%d/" % (base, sub, t),
        "is_read": False, "flag_owntopic": 3, "last_position": POS, "last_post_read_id": READ_ID}


def group(cat, n, name="favorites"):
    items = [item(i, cat=cat) for i in range(n)]
    for it in items:
        it["links"]["category"]["title"] = "Real Category Name"
    return {"page": 1, "results_count": n, "results_per_page": n, "resources": items, "list_type": "topic",
            "type": "list", "href": "%scategories/%d/topics/%s/?page=1&results_per_page=%d" % (API, cat, name, n),
            "links": {"category": link("forum_category", "%scategories/%d/" % (API, cat), title="Real Category Name")}}


def bucket(groups=3, per=3, name="favorites"):
    return json.dumps({"resource": {
        "page": 1, "results_count": groups, "results_per_page": groups,
        "resources": [group(CAT + g, per, name) for g in range(groups)], "list_type": "list", "type": "list",
        "href": "%stopics/%s/?page=1&results_per_page=25" % (API, name)}}).replace("/", "\\/")


def flat(n=4):
    g = group(CAT, n, "participated")
    del g["links"]
    for it in g["resources"]:
        it["links"]["category"].pop("title", None)
    return json.dumps({"resource": g})


def anon(text):
    return A.alias_rest_buckets(text)


def put_back(aliased, value_path, real):
    doc = json.loads(aliased)
    o = doc
    for k in value_path[:-1]:
        o = o[k]
    o[value_path[-1]] = real
    return json.dumps(doc)


class RestBucketAliasTests(unittest.TestCase):
    def test_cut_and_counts_follow(self):
        doc = json.loads(anon(bucket()))["resource"]
        self.assertEqual(len(doc["resources"]), A.REST_KEEP)
        self.assertEqual((doc["results_count"], doc["results_per_page"]), (A.REST_KEEP,) * 2)
        for g in doc["resources"]:
            self.assertEqual(len(g["resources"]), A.REST_KEEP_ITEMS_PER_GROUP)
            self.assertEqual((g["results_count"], g["results_per_page"]), (A.REST_KEEP_ITEMS_PER_GROUP,) * 2)
            self.assertIn("results_per_page=%d" % A.REST_KEEP_ITEMS_PER_GROUP, g["href"])

    def test_a_short_answer_is_refused_not_padded(self):
        for text in (bucket(groups=1, per=1), flat(1), bucket(groups=1, per=3)):
            with self.assertRaises(A.AnonymizeError):
                anon(text)

    def test_published_size_is_fixed(self):
        for real in (2, 3, 5):
            self.assertEqual(len(json.loads(anon(bucket(groups=real, per=1)))["resource"]["resources"]), 2)
            self.assertEqual(len(json.loads(anon(flat(real)))["resource"]["resources"]), 2)

    def test_kept_items_cover_the_shapes_in_document_order(self):
        doc = json.loads(bucket(groups=5, per=3))
        groups = doc["resource"]["resources"]
        groups[1]["resources"][0]["is_read"] = True              # second group: a new shape
        groups[2]["resources"][0]["flag_owntopic"] = 1           # third group: past the limit
        out = json.loads(anon(json.dumps(doc)))["resource"]["resources"]
        kept = [g["resources"][0] for g in out]
        self.assertEqual([it["is_read"] for it in kept], [False, True])
        self.assertEqual([it["flag_owntopic"] for it in kept], [3, 3])
        self.assertEqual([g["links"]["category"]["title"] for g in out], ["Category 1", "Category 2"])

    def test_flat_bucket_keeps_a_few_items(self):
        doc = json.loads(anon(flat()))["resource"]
        self.assertEqual(len(doc["resources"]), A.REST_KEEP)
        self.assertEqual(doc["results_count"], A.REST_KEEP)

    def test_no_real_value_survives(self):
        out = anon(bucket()) + anon(flat())
        for real in (str(TOPIC), str(SUB), str(COUNT), TITLE, "2031-02-03", str(POS), str(READ_ID),
                     "Real Category Name", "categories\\/33\\/", "categories/33/"):
            self.assertNotIn(real, out)

    def test_each_position_is_aliased_by_position(self):
        first = json.loads(anon(bucket()))["resource"]["resources"][0]["resources"][0]
        second = json.loads(anon(bucket()))["resource"]["resources"][1]["resources"][0]
        self.assertEqual((first["id"], second["id"]), (9800001, 9800002))
        self.assertEqual(first["title"], "Followed topic 1")
        self.assertEqual(first["last_post_date"], "2000-01-02 00:01")
        self.assertEqual(first["links"]["posts"]["count"], 5001)
        self.assertEqual(first["last_position"], 201)
        self.assertEqual(first["last_post_read_id"], 9810000001)
        self.assertIn("categories/101/subcategories/960001/topics/9800001/", first["href"])
        self.assertEqual(second["links"]["category"]["href"], API + "categories/102/")
        self.assertIn("page=126&results_per_page=40", first["links"]["posts"]["href"])  # ceil(5001 / 40)

    def test_kept_structure_and_flags(self):
        it = json.loads(anon(bucket()))["resource"]["resources"][0]["resources"][0]
        self.assertEqual(list(it), list(item()))
        self.assertEqual((it["is_read"], it["flag_owntopic"], it["is_closed"]), (False, 3, False))

    def test_category_map_serves_the_capture_url(self):
        cats = {}
        A.alias_rest_buckets(flat(), cats)
        self.assertEqual(cats, {str(CAT): "101"})

    def test_every_dict_kind_has_an_exact_key_set(self):
        top = ["resource", "resources", 0, "resources", 0]
        grp = ["resource", "resources", 0]
        spots = {"top list": ["resource"], "group": grp, "item": top, "forum link": top + ["links", "forum"],
                 "category link": top + ["links", "category"], "posts link": top + ["links", "posts"],
                 "author link": top + ["links", "author"], "item links": top + ["links"],
                 "group links": grp + ["links"], "group category link": grp + ["links", "category"]}
        for name, path in spots.items():
            for extra in ("title", "id", "count", "last_post_date", "note"):
                doc = json.loads(bucket())
                o = doc
                for k in path:
                    o = o[k]
                if extra in o:
                    continue
                o[extra] = "Real Value Qzwx" if extra in ("title", "note", "last_post_date") else 424242
                with self.assertRaises(A.AnonymizeError, msg=name + " " + extra):
                    anon(json.dumps(doc))

    def test_an_author_without_avatar_has_no_tns3(self):
        doc = json.loads(bucket())
        for grp in doc["resource"]["resources"]:
            for it in grp["resources"]:
                for who in ("author", "last_author"):
                    del it["links"][who]["tns3"]
        out = anon(json.dumps(doc))
        self.assertNotIn("avatar", " ".join(r for _l, _c, r in A.verify_rest_buckets(out)))
        self.assertNotIn("tns3", json.loads(out)["resource"]["resources"][0]["resources"][0]["links"]["author"])
        doc["resource"]["resources"][0]["resources"][0]["links"]["author"]["tns3"] = None
        with self.assertRaises(A.AnonymizeError):
            anon(json.dumps(doc))

    def test_constants_are_checked_not_passed_through(self):
        top = ["resource", "resources", 0, "resources", 0]
        for path, real in ((top + ["links", "forum", "href"], API + "categories/33/"), (top + ["type"], "secret"),
                           (top + ["links", "category", "linked_type"], "secret"),
                           (["resource", "resources", 0, "type"], "secret"), (["resource", "type"], "secret"),
                           (top + ["links", "author", "href"], "https://example.org/x")):
            with self.assertRaises(A.AnonymizeError, msg=str(path)):
                anon(put_back(bucket(), path, real))

    def test_markers_stripped_but_request_is_a_bucket(self):
        doc = json.loads(bucket())
        for g in doc["resource"]["resources"]:
            for it in g["resources"]:
                for k in A.REST_BUCKET_MARKERS:
                    it.pop(k, None)
        stripped = json.dumps(doc)
        url = "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/topics/favorites/"
        self.assertEqual(anon(stripped), stripped)  # no marker, no request: not a bucket
        with self.assertRaises(A.AnonymizeError):
            A.alias_rest_buckets(stripped, None, url)
        self.assertTrue(A.verify_rest_buckets(stripped, url))
        self.assertEqual(A.verify_rest_buckets(stripped), [])
        self.assertFalse(A.is_rest_bucket_request("https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/categories/"))

    def test_unknown_field_stops_the_anonymizer(self):
        doc = json.loads(bucket())
        doc["resource"]["resources"][0]["resources"][0]["new_field"] = "x"
        with self.assertRaises(A.AnonymizeError):
            anon(json.dumps(doc))

    def test_other_json_and_html_are_untouched(self):
        for text in ('{"resource": {"id": 1}}', "<html></html>", "[1, 2]"):
            self.assertEqual(anon(text), text)

    def test_meta_url_gets_the_alias_category(self):
        a = A.Anonymizer(A.Config(pseudos=["Pseudoa Realone"]))
        a.anonymize(flat())
        meta = a.anonymize_meta({"url": "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/"
                                        "categories/33/topics/participated/"})
        self.assertIn("categories/101/topics/participated", meta["url"])

    def test_percent_encoded_request_is_a_bucket_request(self):
        for uri in ("forums/hardwarefr/topics/read/", "forums%2Fhardwarefr%2Ftopics%2Fread%2F",
                    "forums%2fhardwarefr%2fcategories%2f16%2ftopics%2fparticipated%2f"):
            self.assertTrue(A.is_rest_bucket_request("https://forum.hardware.fr/webservices/rest_api.php?uri=" + uri), uri)
        self.assertFalse(A.is_rest_bucket_request(
            "https://forum.hardware.fr/webservices/rest_api.php?uri=forums%2Fhardwarefr%2Fcategories%2F"))

    def test_meta_url_with_encoded_slashes_gets_the_alias_category(self):
        a = A.Anonymizer(A.Config())
        a.anonymize(flat())
        url = "https://forum.hardware.fr/webservices/rest_api.php?uri=forums%2Fhardwarefr%2Fcategories%2F33%2Ftopics%2Fparticipated%2F"
        out = a.anonymize_meta({"url": url})["url"]
        self.assertIn("categories%2F101%2Ftopics%2Fparticipated", out)
        self.assertNotIn("33", out)
        self.assertTrue(A.verify_rest_meta(json.dumps({"url": url})))
        self.assertEqual(A.verify_rest_meta(json.dumps({"url": out})), [])

    def test_full_pipeline_output_is_clean(self):
        a = A.Anonymizer(A.Config(pseudos=["Pseudoa Realone", "Pseudob Realtwo"]))
        for text in (bucket(), flat()):
            out = a.anonymize(text)
            self.assertEqual(a.findings(out, account="user1"), [])
            self.assertNotIn("Realone", out)
            self.assertNotIn(AUTHOR_ID, out)
            self.assertNotIn(LAST_ID, out)


class RestBucketVerifierTests(unittest.TestCase):
    """The verifier alone: only one value of an aliased answer is put back."""

    def setUp(self):
        a = A.Anonymizer(A.Config(pseudos=["Pseudoa Realone", "Pseudob Realtwo"]))
        self.good = a.anonymize(bucket())
        self.good_flat = a.anonymize(flat())

    def flagged(self, text):
        return [f for f in A.verify_rest_buckets(text) if "rest-bucket" in f[2]]

    def test_aliased_answer_is_clean(self):
        self.assertEqual(self.flagged(self.good), [])
        self.assertEqual(self.flagged(self.good_flat), [])

    def test_raw_answer_is_reported(self):
        self.assertTrue(self.flagged(bucket()))
        self.assertTrue(self.flagged(flat()))

    def test_each_position(self):
        top = ["resource", "resources", 0, "resources", 0]
        grp = ["resource", "resources", 0]
        cases = {
            "topic id": (top + ["id"], TOPIC),
            "topic id of the wrong position": (top + ["id"], 9800002),
            "title": (top + ["title"], TITLE),
            "date": (top + ["last_post_date"], DATE),
            "date, shape ok": (top + ["last_post_date"], "2000-01-03 00:02"),
            "reply count": (top + ["links", "posts", "count"], COUNT),
            "reply count inside the alias range": (top + ["links", "posts", "count"], 6000),
            "last position": (top + ["last_position"], POS),
            "last position inside the alias range": (top + ["last_position"], 500),
            "last read id": (top + ["last_post_read_id"], READ_ID),
            "topic href": (top + ["href"], "%scategories/101/subcategories/960001/topics/%d/" % (API, TOPIC)),
            "category href": (top + ["links", "category", "href"], "%scategories/%d/" % (API, CAT)),
            "category href of another group": (top + ["links", "category", "href"], "%scategories/102/" % API),
            "subcategory href": (top + ["links", "subcategory", "href"], "%scategories/101/subcategories/%d/" % (API, SUB)),
            "posts href topic": (top + ["links", "posts", "href"],
                                 "%scategories/101/subcategories/960001/topics/%d/posts/?page=126&results_per_page=40" % (API, TOPIC)),
            "posts href page": (top + ["links", "posts", "href"],
                                "%scategories/101/subcategories/960001/topics/9800001/posts/?page=427&results_per_page=40" % API),
            "group category title": (grp + ["links", "category", "title"], "Real Category Name"),
            "group category title of another category": (grp + ["links", "category", "title"], "Category 2"),
            "group href": (grp + ["href"], "%scategories/%d/topics/favorites/?page=1&results_per_page=1" % (API, CAT)),
            "group size in href": (grp + ["href"], "%scategories/101/topics/favorites/?page=1&results_per_page=7" % API),
            "list href": (["resource", "href"], "%stopics/favorites/?page=1&results_per_page=9" % API),
            "avatar": (top + ["links", "author", "tns3"], "mesdiscussions-%s.png" % AUTHOR_ID),
            "results_count": (["resource", "results_count"], 3),
            "results_count below 10": (grp + ["results_count"], 7),
            "results_per_page": (["resource", "results_per_page"], 9),
            "page": (["resource", "page"], 5),
            "type word": (top + ["type"], "secret"),
            "list_type word": (grp + ["list_type"], "secret"),
            "linked_type word": (top + ["links", "category", "linked_type"], "secret"),
            "flag": (top + ["flag_owntopic"], 9),
            "closed": (top + ["is_closed"], "yes"),
            "forum href": (top + ["links", "forum", "href"], API + "categories/33/"),
            "forum type word": (top + ["links", "forum", "linked_type"], "secret"),
            "avatar extension": (top + ["links", "author", "tns3"], "mesdiscussions-900001.exe"),
            "author name": (top + ["links", "author", "title"], "Pseudob Realtwo"),
            "item type word": (top + ["type"], "secret"),
            "list type word, top": (["resource", "type"], "secret")}
        for name, (path, real) in cases.items():
            self.assertTrue(self.flagged(put_back(self.good, path, real)), name)

    def test_meta_url_category(self):
        url = "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/categories/%s/topics/participated/"
        self.assertTrue(A.verify_rest_meta(json.dumps({"url": url % CAT})))
        self.assertTrue(A.verify_rest_meta(json.dumps({"redirects": [{"final_url": url % "16"}]})))
        self.assertEqual(A.verify_rest_meta(json.dumps({"url": url % 101})), [])
        self.assertEqual(A.verify_rest_meta("<html></html>"), [])

    def test_extra_keys_in_every_dict_kind(self):
        top = ["resource", "resources", 0, "resources", 0]
        grp = ["resource", "resources", 0]
        spots = {"top list": ["resource"], "group": grp, "item": top, "forum link": top + ["links", "forum"],
                 "category link": top + ["links", "category"], "posts link": top + ["links", "posts"],
                 "author link": top + ["links", "author"], "item links": top + ["links"],
                 "group links": grp + ["links"], "group category link": grp + ["links", "category"],
                 "document": []}
        for name, path in spots.items():
            for extra, real in (("title", "Real Value Qzwx"), ("id", 424242), ("count", 424242),
                                ("last_post_date", DATE), ("note", "x")):
                doc = json.loads(self.good)
                o = doc
                for k in path:
                    o = o[k]
                if extra in o:
                    continue
                o[extra] = real
                self.assertTrue(self.flagged(json.dumps(doc)), name + " " + extra)

    def test_missing_key_is_reported(self):
        top = ["resource", "resources", 0, "resources", 0]
        doc = json.loads(self.good)
        del doc["resource"]["resources"][0]["resources"][0]["links"]["posts"]
        self.assertTrue(self.flagged(json.dumps(doc)))

    def test_bucket_without_markers_is_checked_through_its_request(self):
        doc = json.loads(self.good)
        for g in doc["resource"]["resources"]:
            for it in g["resources"]:
                for k in A.REST_BUCKET_MARKERS:
                    it.pop(k, None)
        text = json.dumps(doc)
        url = "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/topics/read/"
        self.assertEqual(A.verify_rest_buckets(text), [])
        self.assertTrue(A.verify_rest_buckets(text, url))

    def test_unknown_key_and_null_are_reported(self):
        top = ["resource", "resources", 0, "resources", 0]
        doc = json.loads(self.good)
        doc["resource"]["resources"][0]["resources"][0]["extra"] = "x"
        self.assertTrue(self.flagged(json.dumps(doc)))
        self.assertTrue(self.flagged(put_back(self.good, top + ["title"], None)))

    def test_findings_never_print_the_value(self):
        for _line, _col, reason in A.verify_rest_buckets(bucket()):
            self.assertNotIn(TITLE, reason)
            self.assertNotIn(str(TOPIC), reason)

    def test_check_finds_a_raw_answer_without_config(self):
        a = A.Anonymizer(A.Config())
        self.assertTrue(any("rest-bucket" in f[2] for f in a.findings(bucket())))

    def test_check_uses_the_meta_url_of_a_corpus_file(self):
        import tempfile
        a = A.Anonymizer(A.Config())
        doc = json.loads(self.good)
        for g in doc["resource"]["resources"]:
            for it in g["resources"]:
                for k in A.REST_BUCKET_MARKERS:
                    it.pop(k, None)
        with tempfile.TemporaryDirectory() as d:
            doc["resource"]["resources"][0]["resources"][0]["id"] = 424242
            with open(os.path.join(d, "X1-b.json"), "w") as fh:
                json.dump(doc, fh)
            with open(os.path.join(d, "X1.meta.json"), "w") as fh:
                json.dump({"id": "X1", "file": "X1-b.json", "private": False, "account": "user1",
                           "final_url": "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/topics/read/"}, fh)
            ((_, _, _), (path, _, _)) = A.corpus_entries(d)
            self.assertEqual(A.meta_urls(d, {})["X1-b.json"].split("uri=")[1], "forums/hardwarefr/topics/read/")
            with open(path) as fh:
                self.assertTrue(A.verify_rest_buckets(fh.read(), A.meta_urls(d, {})["X1-b.json"]))


if __name__ == "__main__":
    unittest.main()
