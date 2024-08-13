defmodule PlausibleWeb.Api.ExternalStatsController.QueryImportedTest do
  use PlausibleWeb.ConnCase

  @user_id 1231

  setup [:create_user, :create_new_site, :create_api_key, :use_api_key]

  describe "aggregation with imported data" do
    setup :create_site_import

    test "does not count imported stats unless specified", %{
      conn: conn,
      site: site,
      site_import: site_import
    } do
      populate_stats(site, site_import.id, [
        build(:imported_visitors, date: ~D[2023-01-01]),
        build(:pageview, timestamp: ~N[2023-01-01 00:00:00])
      ])

      query_params = %{
        "site_id" => site.domain,
        "date_range" => "all",
        "metrics" => ["pageviews"]
      }

      conn1 = post(conn, "/api/v2/query", query_params)

      assert json_response(conn1, 200)["results"] == [%{"metrics" => [1], "dimensions" => []}]

      conn2 = post(conn, "/api/v2/query", Map.put(query_params, "include", %{"imports" => true}))

      assert json_response(conn2, 200)["results"] == [%{"metrics" => [2], "dimensions" => []}]
      refute json_response(conn2, 200)["meta"]["warning"]
    end
  end

  test "breaks down all metrics by visit:referrer with imported data", %{conn: conn, site: site} do
    site_import =
      insert(:site_import,
        site: site,
        start_date: ~D[2005-01-01],
        end_date: Timex.today(),
        source: :universal_analytics
      )

    populate_stats(site, site_import.id, [
      build(:pageview, referrer: "site.com", timestamp: ~N[2021-01-01 00:00:00]),
      build(:pageview, referrer: "site.com/1", timestamp: ~N[2021-01-01 00:00:00]),
      build(:imported_sources,
        referrer: "site.com",
        date: ~D[2021-01-01],
        visitors: 2,
        visits: 2,
        pageviews: 2,
        bounces: 1,
        visit_duration: 120
      ),
      build(:imported_sources,
        referrer: "site.com/2",
        date: ~D[2021-01-01],
        visitors: 2,
        visits: 2,
        pageviews: 2,
        bounces: 2,
        visit_duration: 0
      ),
      build(:imported_sources,
        date: ~D[2021-01-01],
        visitors: 10,
        visits: 11,
        pageviews: 50,
        bounces: 0,
        visit_duration: 1100
      )
    ])

    conn =
      post(conn, "/api/v2/query", %{
        "site_id" => site.domain,
        "metrics" => ["visitors", "visits", "pageviews", "bounce_rate", "visit_duration"],
        "date_range" => "all",
        "dimensions" => ["visit:referrer"],
        "include" => %{"imports" => true}
      })

    assert json_response(conn, 200)["results"] == [
             %{"dimensions" => ["Direct / None"], "metrics" => [10, 11, 50, 0.0, 100.0]},
             %{"dimensions" => ["site.com"], "metrics" => [3, 3, 3, 67.0, 40.0]},
             %{"dimensions" => ["site.com/2"], "metrics" => [2, 2, 2, 100.0, 0.0]},
             %{"dimensions" => ["site.com/1"], "metrics" => [1, 1, 1, 100.0, 0.0]}
           ]
  end

  test "breaks down all metrics by visit:utm_source with imported data", %{conn: conn, site: site} do
    site_import =
      insert(:site_import,
        site: site,
        start_date: ~D[2005-01-01],
        end_date: Timex.today(),
        source: :universal_analytics
      )

    populate_stats(site, site_import.id, [
      build(:pageview, utm_source: "SomeUTMSource", timestamp: ~N[2021-01-01 00:00:00]),
      build(:pageview, utm_source: "SomeUTMSource-1", timestamp: ~N[2021-01-01 00:00:00]),
      build(:imported_sources,
        utm_source: "SomeUTMSource",
        date: ~D[2021-01-01],
        visitors: 2,
        visits: 2,
        pageviews: 2,
        bounces: 1,
        visit_duration: 120
      ),
      build(:imported_sources,
        utm_source: "SomeUTMSource-2",
        date: ~D[2021-01-01],
        visitors: 2,
        visits: 2,
        pageviews: 2,
        bounces: 2,
        visit_duration: 0
      ),
      build(:imported_sources,
        date: ~D[2021-01-01],
        visitors: 10,
        visits: 11,
        pageviews: 50,
        bounces: 0,
        visit_duration: 1100
      )
    ])

    conn =
      post(conn, "/api/v2/query", %{
        "site_id" => site.domain,
        "metrics" => ["visitors", "visits", "pageviews", "bounce_rate", "visit_duration"],
        "date_range" => "all",
        "dimensions" => ["visit:utm_source"],
        "include" => %{"imports" => true}
      })

    %{"results" => results} = json_response(conn, 200)

    assert results == [
             %{"dimensions" => ["SomeUTMSource"], "metrics" => [3, 3, 3, 67.0, 40.0]},
             %{"dimensions" => ["SomeUTMSource-2"], "metrics" => [2, 2, 2, 100.0, 0.0]},
             %{"dimensions" => ["SomeUTMSource-1"], "metrics" => [1, 1, 1, 100.0, 0.0]}
           ]
  end

  test "pageviews breakdown by event:page - imported data having pageviews=0 and visitors=n should be bypassed",
       %{conn: conn, site: site} do
    site_import =
      insert(:site_import,
        site: site,
        start_date: ~D[2005-01-01],
        end_date: Timex.today(),
        source: :universal_analytics
      )

    populate_stats(site, site_import.id, [
      build(:pageview, pathname: "/", timestamp: ~N[2021-01-01 00:00:00]),
      build(:pageview, pathname: "/", timestamp: ~N[2021-01-01 00:25:00]),
      build(:pageview,
        pathname: "/plausible.io",
        timestamp: ~N[2021-01-01 00:00:00]
      ),
      build(:imported_pages,
        page: "/skip-me",
        date: ~D[2021-01-01],
        visitors: 1,
        pageviews: 0
      ),
      build(:imported_pages,
        page: "/include-me",
        date: ~D[2021-01-01],
        visitors: 1,
        pageviews: 1
      )
    ])

    conn =
      post(conn, "/api/v2/query", %{
        "site_id" => site.domain,
        "metrics" => ["pageviews"],
        "date_range" => "all",
        "dimensions" => ["event:page"],
        "include" => %{"imports" => true}
      })

    assert json_response(conn, 200)["results"] == [
             %{"dimensions" => ["/"], "metrics" => [2]},
             %{"dimensions" => ["/plausible.io"], "metrics" => [1]},
             %{"dimensions" => ["/include-me"], "metrics" => [1]}
           ]
  end

  describe "breakdown by visit:exit_page with" do
    setup %{site: site} do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:pageview,
          pathname: "/a",
          timestamp: ~N[2021-01-01 00:00:00]
        ),
        build(:pageview,
          user_id: @user_id,
          pathname: "/a",
          timestamp: ~N[2021-01-01 00:25:00]
        ),
        build(:pageview,
          user_id: @user_id,
          pathname: "/b",
          timestamp: ~N[2021-01-01 00:35:00]
        ),
        build(:imported_exit_pages,
          exit_page: "/b",
          exits: 3,
          visitors: 2,
          pageviews: 5,
          date: ~D[2021-01-01]
        )
      ])
    end

    test "can query with visit:exit_page dimension", %{conn: conn, site: site} do
      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visits"],
          "date_range" => "all",
          "dimensions" => ["visit:exit_page"],
          "include" => %{"imports" => true}
        })

      %{"results" => results} = json_response(conn, 200)

      assert results == [
               %{"dimensions" => ["/b"], "metrics" => [4]},
               %{"dimensions" => ["/a"], "metrics" => [1]}
             ]
    end
  end

  describe "imported data" do
    test "returns screen sizes breakdown when filtering by screen size", %{conn: conn, site: site} do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:pageview,
          timestamp: ~N[2021-01-01 00:00:01],
          screen_size: "Mobile"
        ),
        build(:imported_devices,
          device: "Mobile",
          visitors: 3,
          pageviews: 5,
          date: ~D[2021-01-01]
        )
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors", "pageviews"],
          "date_range" => "all",
          "dimensions" => ["visit:device"],
          "filters" => [
            ["is", "visit:device", ["Mobile"]]
          ],
          "include" => %{"imports" => true}
        })

      %{"results" => results} = json_response(conn, 200)

      assert results == [%{"dimensions" => ["Mobile"], "metrics" => [4, 6]}]
    end

    test "returns custom event goals and pageview goals", %{conn: conn, site: site} do
      insert(:goal, site: site, event_name: "Purchase")
      insert(:goal, site: site, page_path: "/test")

      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:pageview,
          timestamp: ~N[2021-01-01 00:00:01],
          pathname: "/test"
        ),
        build(:event,
          name: "Purchase",
          timestamp: ~N[2021-01-01 00:00:03]
        ),
        build(:event,
          name: "Purchase",
          timestamp: ~N[2021-01-01 00:00:03]
        ),
        build(:imported_custom_events,
          name: "Purchase",
          visitors: 3,
          events: 5,
          date: ~D[2021-01-01]
        ),
        build(:imported_pages,
          page: "/test",
          visitors: 2,
          pageviews: 2,
          date: ~D[2021-01-01]
        ),
        build(:imported_visitors, visitors: 5, date: ~D[2021-01-01])
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "date_range" => "all",
          "dimensions" => ["event:goal"],
          "metrics" => ["visitors", "events", "pageviews", "conversion_rate"],
          "include" => %{"imports" => true}
        })

      assert json_response(conn, 200)["results"] == [
               %{"dimensions" => ["Purchase"], "metrics" => [5, 7, 0, 62.5]},
               %{"dimensions" => ["Visit /test"], "metrics" => [3, 3, 3, 37.5]}
             ]
    end

    test "pageviews are returned as events for breakdown reports other than custom events", %{
      conn: conn,
      site: site
    } do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:imported_browsers, browser: "Chrome", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_devices, device: "Desktop", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_entry_pages, entry_page: "/test", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_exit_pages, exit_page: "/test", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_locations, country: "EE", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_operating_systems,
          operating_system: "Mac",
          pageviews: 1,
          date: ~D[2021-01-01]
        ),
        build(:imported_pages, page: "/test", pageviews: 1, date: ~D[2021-01-01]),
        build(:imported_sources, source: "Google", pageviews: 1, date: ~D[2021-01-01])
      ])

      breakdown_and_first = fn dimension ->
        conn
        |> post("/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["events"],
          "date_range" => ["2021-01-01", "2021-01-01"],
          "dimensions" => [dimension],
          "include" => %{"imports" => true}
        })
        |> json_response(200)
        |> Map.get("results")
        |> List.first()
      end

      assert %{"dimensions" => ["Chrome"], "metrics" => [1]} =
               breakdown_and_first.("visit:browser")

      assert %{"dimensions" => ["Desktop"], "metrics" => [1]} =
               breakdown_and_first.("visit:device")

      assert %{"dimensions" => ["EE"], "metrics" => [1]} = breakdown_and_first.("visit:country")
      assert %{"dimensions" => ["Mac"], "metrics" => [1]} = breakdown_and_first.("visit:os")
      assert %{"dimensions" => ["/test"], "metrics" => [1]} = breakdown_and_first.("event:page")

      assert %{"dimensions" => ["Google"], "metrics" => [1]} =
               breakdown_and_first.("visit:source")
    end

    for goal_name <- Plausible.Imported.goals_with_url() do
      test "returns url breakdown for #{goal_name} goal", %{conn: conn, site: site} do
        insert(:goal, event_name: unquote(goal_name), site: site)
        site_import = insert(:site_import, site: site)

        populate_stats(site, site_import.id, [
          build(:event,
            name: unquote(goal_name),
            "meta.key": ["url"],
            "meta.value": ["https://one.com"]
          ),
          build(:imported_custom_events,
            name: unquote(goal_name),
            visitors: 2,
            events: 5,
            link_url: "https://one.com"
          ),
          build(:imported_custom_events,
            name: unquote(goal_name),
            visitors: 5,
            events: 10,
            link_url: "https://two.com"
          ),
          build(:imported_custom_events,
            name: "some goal",
            visitors: 5,
            events: 10
          ),
          build(:imported_visitors, visitors: 9)
        ])

        conn =
          post(conn, "/api/v2/query", %{
            "site_id" => site.domain,
            "metrics" => ["visitors", "events", "conversion_rate"],
            "date_range" => "all",
            "dimensions" => ["event:props:url"],
            "filters" => [
              ["is", "event:goal", [unquote(goal_name)]]
            ],
            "include" => %{"imports" => true}
          })

        assert json_response(conn, 200)["results"] == [
                 %{"dimensions" => ["https://two.com"], "metrics" => [5, 10, 50]},
                 %{"dimensions" => ["https://one.com"], "metrics" => [3, 6, 30]}
               ]

        refute json_response(conn, 200)["meta"]["warning"]
      end
    end

    for goal_name <- Plausible.Imported.goals_with_path() do
      test "returns path breakdown for #{goal_name} goal", %{conn: conn, site: site} do
        insert(:goal, event_name: unquote(goal_name), site: site)
        site_import = insert(:site_import, site: site)

        populate_stats(site, site_import.id, [
          build(:event,
            name: unquote(goal_name),
            "meta.key": ["path"],
            "meta.value": ["/one"]
          ),
          build(:imported_custom_events,
            name: unquote(goal_name),
            visitors: 2,
            events: 5,
            path: "/one"
          ),
          build(:imported_custom_events,
            name: unquote(goal_name),
            visitors: 5,
            events: 10,
            path: "/two"
          ),
          build(:imported_custom_events,
            name: "some goal",
            visitors: 5,
            events: 10
          ),
          build(:imported_visitors, visitors: 9)
        ])

        conn =
          post(conn, "/api/v2/query", %{
            "site_id" => site.domain,
            "metrics" => ["visitors", "events", "conversion_rate"],
            "date_range" => "all",
            "dimensions" => ["event:props:path"],
            "filters" => [
              ["is", "event:goal", [unquote(goal_name)]]
            ],
            "include" => %{"imports" => true}
          })

        assert json_response(conn, 200)["results"] == [
                 %{"dimensions" => ["/two"], "metrics" => [5, 10, 50]},
                 %{"dimensions" => ["/one"], "metrics" => [3, 6, 30]}
               ]

        refute json_response(conn, 200)["meta"]["warning"]
      end
    end

    test "adds a warning when query params are not supported for imported data", %{
      conn: conn,
      site: site
    } do
      site_import = insert(:site_import, site: site)

      insert(:goal, event_name: "Signup", site: site)

      populate_stats(site, site_import.id, [
        build(:event,
          name: "Signup",
          "meta.key": ["package"],
          "meta.value": ["large"]
        ),
        build(:imported_visitors, visitors: 9)
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "all",
          "dimensions" => ["event:props:package"],
          "filters" => [
            ["is", "event:goal", ["Signup"]]
          ],
          "include" => %{"imports" => true}
        })

      assert json_response(conn, 200)["results"] == [
               %{"dimensions" => ["large"], "metrics" => [1]}
             ]

      assert json_response(conn, 200)["meta"]["warning"] =~
               "Imported stats are not included in the results because query parameters are not supported."
    end

    test "does not add a warning when there are no site imports", %{conn: conn, site: site} do
      insert(:goal, event_name: "Signup", site: site)

      populate_stats(site, [
        build(:event,
          name: "Signup",
          "meta.key": ["package"],
          "meta.value": ["large"]
        )
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "all",
          "dimensions" => ["event:props:package"],
          "filters" => [
            ["is", "event:goal", ["Signup"]]
          ],
          "include" => %{"imports" => true}
        })

      refute json_response(conn, 200)["meta"]["warning"]
    end

    test "does not add a warning when import is out of queried date range", %{
      conn: conn,
      site: site
    } do
      site_import = insert(:site_import, site: site, end_date: Date.add(Date.utc_today(), -3))

      insert(:goal, event_name: "Signup", site: site)

      populate_stats(site, site_import.id, [
        build(:event,
          name: "Signup",
          "meta.key": ["package"],
          "meta.value": ["large"]
        ),
        build(:imported_visitors, visitors: 9)
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "day",
          "dimensions" => ["event:props:package"],
          "filters" => [
            ["is", "event:goal", ["Signup"]]
          ],
          "include" => %{"imports" => true}
        })

      refute json_response(conn, 200)["meta"]["warning"]
    end

    test "applies multiple filters if the properties belong to the same table", %{
      conn: conn,
      site: site
    } do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:imported_sources, source: "Google", utm_medium: "organic", utm_term: "one"),
        build(:imported_sources, source: "Twitter", utm_medium: "organic", utm_term: "two"),
        build(:imported_sources,
          source: "Facebook",
          utm_medium: "something_else",
          utm_term: "one"
        )
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "day",
          "dimensions" => ["visit:source"],
          "filters" => [
            ["is", "visit:utm_medium", ["organic"]],
            ["is", "visit:utm_term", ["one"]]
          ],
          "include" => %{"imports" => true}
        })

      assert json_response(conn, 200)["results"] == [
               %{"dimensions" => ["Google"], "metrics" => [1]}
             ]
    end

    test "ignores imported data if filtered property belongs to a different table than the breakdown property",
         %{
           conn: conn,
           site: site
         } do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:imported_sources, source: "Google"),
        build(:imported_devices, device: "Desktop")
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "day",
          "dimensions" => ["visit:source"],
          "filters" => [
            ["is", "visit:device", ["Desktop"]]
          ],
          "include" => %{"imports" => true}
        })

      assert %{
               "results" => [],
               "meta" => meta
             } = json_response(conn, 200)

      assert meta["warning"] =~ "Imported stats are not included in the results"
    end

    test "imported country, region and city data",
         %{
           conn: conn,
           site: site
         } do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:pageview,
          timestamp: ~N[2021-01-01 00:15:00],
          country_code: "DE",
          subdivision1_code: "DE-BE",
          city_geoname_id: 2_950_159
        ),
        build(:pageview,
          timestamp: ~N[2021-01-01 00:15:00],
          country_code: "DE",
          subdivision1_code: "DE-BE",
          city_geoname_id: 2_950_159
        ),
        build(:pageview,
          timestamp: ~N[2021-01-01 00:15:00],
          country_code: "EE",
          subdivision1_code: "EE-37",
          city_geoname_id: 588_409
        ),
        build(:imported_locations, country: "EE", region: "EE-37", city: 588_409, visitors: 33)
      ])

      for {dimension, stats_value, imports_value} <- [
            {"visit:country", "DE", "EE"},
            {"visit:region", "DE-BE", "EE-37"},
            {"visit:city", 2_950_159, 588_409},
            {"visit:country_name", "Germany", "Estonia"},
            {"visit:region_name", "Berlin", "Harjumaa"},
            {"visit:city_name", "Berlin", "Tallinn"}
          ] do
        conn =
          post(conn, "/api/v2/query", %{
            "site_id" => site.domain,
            "metrics" => ["visitors"],
            "date_range" => "all",
            "dimensions" => [dimension],
            "include" => %{"imports" => true}
          })

        assert json_response(conn, 200)["results"] == [
                 %{"dimensions" => [imports_value], "metrics" => [34]},
                 %{"dimensions" => [stats_value], "metrics" => [2]}
               ]
      end
    end

    test "imported country and city names", %{
      site: site,
      conn: conn
    } do
      site_import = insert(:site_import, site: site)

      populate_stats(site, site_import.id, [
        build(:pageview,
          country_code: "GB",
          # London
          city_geoname_id: 2_643_743
        ),
        build(:pageview,
          country_code: "CA",
          # Different London
          city_geoname_id: 6_058_560
        ),
        build(:imported_locations, country: "GB", city: 2_643_743, visitors: 33)
      ])

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "all",
          "dimensions" => ["visit:city_name"],
          "include" => %{"imports" => true}
        })

      assert json_response(conn, 200)["results"] == [
               %{"dimensions" => ["London"], "metrics" => [35]}
             ]

      conn =
        post(conn, "/api/v2/query", %{
          "site_id" => site.domain,
          "metrics" => ["visitors"],
          "date_range" => "all",
          "dimensions" => ["visit:city_name", "visit:country_name"],
          "include" => %{"imports" => true}
        })

      assert json_response(conn, 200)["results"] == [
               %{"dimensions" => ["London", "United Kingdom"], "metrics" => [34]},
               %{"dimensions" => ["London", "Canada"], "metrics" => [1]}
             ]
    end
  end
end
