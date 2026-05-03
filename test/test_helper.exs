ExUnit.configure(exclude: [:integration, :load, :nats_live])
ExUnit.start()

Mox.defmock(BotArmyRpg.CharacterStoreMock, for: BotArmyRpg.CharacterStoreBehaviour)
Mox.defmock(BotArmyRpg.SessionStoreMock, for: BotArmyRpg.SessionStoreBehaviour)
Mox.defmock(BotArmyRpg.SceneFactStoreMock, for: BotArmyRpg.SceneFactStoreBehaviour)
Mox.defmock(BotArmyRpg.ThemeStoreMock, for: BotArmyRpg.ThemeStoreBehaviour)
