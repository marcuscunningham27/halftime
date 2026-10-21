import Foundation
import Testing
@testable import SportsKit

@Suite struct SleeperTests {
    @Test func unknownUsernameIsNil() throws {
        #expect(try Sleeper.parseUserID(Data("null".utf8)) == nil)
        #expect(try Sleeper.parseUserID(Data(#"{"user_id":"123","display_name":"marcus"}"#.utf8)) == "123")
    }

    @Test func findsMyRosterAndDropsEmptySlots() throws {
        let json = #"""
        [{"owner_id":"9","players":["1"],"starters":["1"]},
         {"owner_id":"123","co_owners":null,"players":["4046","KC","17"],"starters":["4046","0","KC"]}]
        """#
        let roster = try #require(try Sleeper.parseRoster(Data(json.utf8), userID: "123"))
        #expect(roster.players == ["4046", "KC", "17"])
        #expect(roster.starters == ["4046", "KC"])
        #expect(roster.lineup == ["4046", nil, "KC"])
        #expect(roster.bench == ["17"])
        #expect(try Sleeper.parseRoster(Data(json.utf8), userID: "nobody") == nil)
    }

    @Test func mergesPointsAcrossMatchups() throws {
        let json = #"[{"players_points":{"4046":21.5}},{"players_points":{"17":8.1}},{"players_points":null}]"#
        #expect(try Sleeper.parsePoints(Data(json.utf8)) == ["4046": 21.5, "17": 8.1])
    }

    @Test func slimsPlayersAndMapsWashington() throws {
        let json = #"""
        {"4046":{"full_name":"Patrick Mahomes","team":"KC","position":"QB","espn_id":3139477},
         "WAS":{"first_name":"Washington","last_name":"Commanders","team":"WAS","position":"DEF"}}
        """#
        let players = try Sleeper.parsePlayers(Data(json.utf8))
        #expect(players["4046"]?.espnID == "3139477")
        #expect(players["4046"]?.photoURL?.absoluteString == "https://a.espncdn.com/i/headshots/nfl/players/full/3139477.png")
        #expect(players["WAS"]?.photoURL?.absoluteString == "https://sleepercdn.com/content/nfl/players/thumb/WAS.jpg")
        #expect(players["WAS"]?.name == "Washington Commanders")
        #expect(players["WAS"]?.team == "WSH")
    }

    @Test func weekFromSeasonStart() throws {
        let state = try Sleeper.parseState(Data(#"{"season":"2026","season_start_date":"2026-09-09","week":7}"#.utf8))
        let day: (String) -> Date = { ISO8601DateFormatter().date(from: $0)! }
        #expect(Sleeper.week(of: day("2026-09-11T00:20:00Z"), state: state) == 1) // opening Thursday night
        #expect(Sleeper.week(of: day("2026-10-20T00:15:00Z"), state: state) == 6) // a Monday night game
        #expect(Sleeper.week(of: day("2026-10-23T00:15:00Z"), state: state) == 7) // the next Thursday
    }

    @Test func namesMatchAcrossSpellings() {
        #expect(Sleeper.sameName("Kenneth Walker", "Kenneth Walker III"))
        #expect(Sleeper.sameName("D.J. Moore", "DJ Moore"))
        #expect(Sleeper.sameName("Amon-Ra St. Brown", "Amon-Ra St. Brown"))
        #expect(!Sleeper.sameName("Josh Allen", "Joshua Allen"))
    }

    @Test func lineupSlotsSkipReserveSpots() throws {
        let json = #"{"roster_positions":["QB","RB","FLEX","DEF","BN","BN","IR","TAXI"]}"#
        #expect(try Sleeper.parseLineupSlots(Data(json.utf8)) == ["QB", "RB", "FLEX", "DEF"])
    }

    @Test func projectionsUseLeagueScoringRules() throws {
        let scoring = try Sleeper.parseScoring(Data(#"{"scoring_settings":{"pass_yd":0.04,"pass_td":4,"rec":0.5,"rec_yd":0.1}}"#.utf8))
        // 250 yards and 2 TDs passing: 10 + 8. A receiver: 5 catches (2.5) and 60 yards (6). Stats outside the rules don't count.
        let projections = #"""
        [{"player_id":"4046","stats":{"pass_yd":250,"pass_td":2,"pts_half_ppr":99}},
         {"player_id":"17","stats":{"rec":5,"rec_yd":60,"rec_td":null}},
         {"player_id":"KC","stats":{}}]
        """#
        let points = try Sleeper.parseProjections(Data(projections.utf8), scoring: scoring)
        #expect(abs((points["4046"] ?? 0) - 18) < 0.0001)
        #expect(abs((points["17"] ?? 0) - 8.5) < 0.0001)
        #expect(points["KC"] == 0)
    }

    @Test func matchupPairsRostersAndSumsStarterProjections() throws {
        let rosters = #"[{"roster_id":1,"owner_id":"me"},{"roster_id":2,"owner_id":"them"},{"roster_id":3,"owner_id":"other"}]"#
        let users = #"""
        [{"user_id":"me","display_name":"Cunners27","avatar":"abc","metadata":{"team_name":"Naberhood Watch"}},
         {"user_id":"them","display_name":"CorbosCrusaders","metadata":{"avatar":"https://sleepercdn.com/uploads/x.jpg"}}]
        """#
        let matchups = #"""
        [{"roster_id":1,"matchup_id":4,"points":94.2,"starters":["4046","0","KC"]},
         {"roster_id":2,"matchup_id":4,"points":84.3,"starters":["17"]},
         {"roster_id":3,"matchup_id":5,"points":70,"starters":[]}]
        """#
        let matchup = try #require(try Sleeper.parseMatchup(rosters: Data(rosters.utf8), users: Data(users.utf8), matchups: Data(matchups.utf8),
                                                            userID: "me", projections: ["4046": 15.5, "KC": 7, "17": 10]))
        #expect(matchup.me.teamName == "Naberhood Watch" && matchup.me.manager == "Cunners27")
        #expect(matchup.me.avatarURL?.absoluteString == "https://sleepercdn.com/avatars/thumbs/abc")
        #expect(matchup.me.points == 94.2 && matchup.me.projected == 22.5)
        let opponent = try #require(matchup.opponent)
        #expect(opponent.teamName == "Team CorbosCrusaders" && opponent.projected == 10)
        #expect(opponent.avatarURL?.absoluteString == "https://sleepercdn.com/uploads/x.jpg")
    }

    @Test func winProbabilityFromProjections() {
        func side(_ projected: Double) -> FantasyMatchup.Side {
            .init(teamName: "", manager: nil, avatarURL: nil, points: 0, projected: projected)
        }
        #expect(FantasyMatchup(me: side(100), opponent: side(100)).winProbability == 0.5)
        let close = FantasyMatchup(me: side(94.97), opponent: side(97.36)).winProbability ?? 0
        #expect((0.47...0.49).contains(close)) // Sleeper showed 48% for this matchup
        #expect((FantasyMatchup(me: side(130), opponent: side(80)).winProbability ?? 0) > 0.85)
        #expect(FantasyMatchup(me: side(100), opponent: nil).winProbability == nil)
    }
}
