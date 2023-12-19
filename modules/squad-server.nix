{ config, lib, pkgs, ... }:
let
  cfg = config.services.squad-server;
  settingsFormat = pkgs.formats.keyValue { };
  replaceNonAlum = rep: str: (builtins.foldl' (x: y: if builtins.isString y then x + y else x + rep)
    ""
    (builtins.split "[^[:alnum:]]" str));
in
{
  options.services.squad-server = {
    servers = lib.mkOption {
      description = ''
        The squad servers to create and run.

        Defined as `servers.<name>`. By default the `<name>` will be used as the
        `servers.<name>.config.server.settings.ServerName`.
      '';
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = rec {
          enable = lib.mkEnableOption "Enable Squad Server";
          openFirewall = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to open ports in the firewall for the server.
            '';
          };
          gamePort = lib.mkOption {
            type = lib.types.port;
            default = 7787;
            apply = (port: [ port (port + 1) ]);
            description = ''
              The server's game port. This will open the port specified here and the `gamePort + 1` as
              Squad needs both open.
            '';
          };

          queryPort = lib.mkOption {
            type = lib.types.port;
            apply = (port: [ port (port + 1) ]);
            default = 27165;
            description = ''
              The server's query port. This will open the port specified here and the `queryPort + 1` as
              Squad needs both open.
            '';
          };

          rconPort = lib.mkOption {
            type = lib.types.port;
            apply = (port: [ port ]);
            default = 21114;
            description = ''
              The server's rcon port. This is needed for remote administration of the server.
            '';
          };

          beaconPort = lib.mkOption {
            type = lib.types.port;
            apply = (port: [ port ]);
            default = 15000;
            description = ''
              The server's Epic Online Services beacon port.
            '';
          };

          stateDir = lib.mkOption {
            type = lib.types.str;
            default = "squad/${replaceNonAlum "_" name}";
            description = ''
              State directory for the systemd user service. This is where the Squad Server will be
              installed to along with configuration.
            '';
          };

          cacheDir = lib.mkOption {
            type = lib.types.str;
            default = "squad/${replaceNonAlum "_" name}";
            description = ''
              State directory for the systemd user service.
            '';
          };

          mods = lib.mkOption {
            # TODO: Better define requirements for a mod id beyond being a positive integer
            type = lib.types.listOf lib.types.ints.positive;
            default = [ ];
            description = ''
              A list of mods to install to the server via their ids.

              A mod example would be `1959152751`, which is the Middle East Escalation mod for
              Squad. It can be found at this link:
              https://steamcommunity.com/sharedfiles/filedetails/?id=1959152751.
            '';
          };

          config = {
            rcon = {
              settings = lib.mkOption {
                description = ''
                  Options to be defined in Rcon.cfg.

                  See https://squad.fandom.com/wiki/Server_Configuration#Rcon_control_in_Rcon.cfg for more
                  details.
                '';
                default = { };
                type = lib.types.submodule {
                  freeformType = settingsFormat.type;
                  options = {
                    IP = lib.mkOption {
                      type = lib.types.str;
                      default = "0.0.0.0";
                      description = ''
                        IP to bind the RCON socket to an alternate IP address.
                      '';
                    };
                    MaxConnections = lib.mkOption {
                      type = lib.types.ints.positive;
                      default = 5;
                      description = ''
                        Maximum number of allowable concurrent RCON connections
                      '';
                    };
                    Password = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = ''
                        The password to provide to RCON. If this is empty (default) then RCON is disabled.
                        Prefer the `config.rcon.passwordFile` option so the password is not copied into
                        the Nix Store.
                      '';
                    };
                    ConnectionTimeout = lib.mkOption {
                      type =
                        lib.types.addCheck lib.types.ints.unsigned (x: x <= 86400);
                      default = 300;
                      description = ''
                        Number of seconds without contact from a connected console before the server
                        checks to see if the session is still active or if it got disconnected. Supports
                        values between 0 and 86400 (1 day). Set to zero to disable the timeout.
                      '';
                    };
                    SecondsBeforeTimeoutCheck = lib.mkOption {
                      type = lib.types.addCheck lib.types.ints.positive
                        (x: x >= 30 && x <= 3600);
                      default = 120;
                      description = ''
                        Number of seconds without contact from a connected console before the server sends
                        a TCP KEEPALIVE to check if the session is still active or if it dog disconnected.
                        Supports values between 30 and 3600 (1 hour).
                      '';
                    };
                    AuthenticationTimeout = lib.mkOption {
                      type =
                        lib.types.addCheck lib.types.ints.unsigned (x: x <= 3600);
                      default = 5;
                      description = ''
                        Number of seconds the server will wait for the console to authenticate when a
                        connection has been established. Supports values between 0 and 3600 (1 hour). Set
                        to zero to disable the timeout.
                      '';
                    };
                  };
                };
              };

              passwordFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "The file to read the rcon password from.";
              };
            };

            admins = lib.mkOption {
              description = ''
                Groups to be defined in the Admin config along with users in the groups.
              '';
              default = { };
              apply = groups: lib.attrsets.foldlAttrs
                (acc: groupName: group: ''
                  ${acc}${lib.optionalString (group.comment != null) ''
                  // ${lib.concatStringsSep "\n// " (lib.splitString "\n" (lib.removeSuffix "\n" group.comment))}''}
                  Group=${groupName}:${lib.concatStringsSep "," group.accessLevels}
                  ${builtins.foldl' (acc: user: ''
                  ${acc}Admin=${user.id}:${groupName} ${lib.optionalString (user.comment != null) "// ${user.comment}"}
                  '') "" group.members}
                '') ""
                groups;
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  comment = lib.mkOption {
                    type = lib.types.nullOr lib.types.lines;
                    default = null;
                    description = ''
                      Optionally add a comment for the group in the Admin config.
                    '';
                  };

                  accessLevels = lib.mkOption {
                    type = lib.types.listOf (lib.types.enum [
                      "startvote"
                      "changemap"
                      "pause"
                      "cheat"
                      "private"
                      "balance"
                      "chat"
                      "kick"
                      "ban"
                      "config"
                      "cameraman"
                      "immune"
                      "manageserver"
                      "featuretest"
                      "reserve"
                      "demos"
                      "clientdemos"
                      "debug"
                      "teamchange"
                      "forceteamchange"
                      "canseeadminchat"
                    ]);
                    default = [ ];
                    description = ''
                      A list of strings relating to valid access levels for admins in Squad's
                      admin config.

                      Valid access levels are:
                        startvote       - Not used
                        changemap       - Change the current map or set the next map
                        pause           - Pause server gameplay
                        cheat           - Use server cheat commands
                        private         - Password protect server
                        balance         - Group Ignores server team balance
                        chat            - Admin chat and Server broadcast
                        kick            - Kick players from the server
                        ban             - Ban players from the server
                        config          - Change server config
                        cameraman       - Admin spectate mode
                        immune          - Cannot be kicked / banned
                        manageserver    - Shutdown server
                        featuretest     - Any features added for testing by dev team
                        reserve         - Reserve slot
                        demos           - Record Demos on the server side via admin commands
                        clientdemos     - Record Demos on the client side via commands or the replay UI.
                        debug           - show admin stats command and other debugging info
                        teamchange      - No timer limits on team change
                        forceteamchange - Can issue the ForceTeamChange command
                        canseeadminchat - This group can see the admin chat and teamkill/admin-join notifications
                    '';
                  };

                  members = lib.mkOption {
                    description = ''
                      Members that are in the group.
                    '';
                    default = [ ];
                    type = lib.types.listOf (lib.types.submodule {
                      options = {
                        # TODO: Improve constraints to ensure this is a steam64 id
                        id = lib.mkOption {
                          type = lib.types.ints.positive;
                          apply = (val: builtins.toString val);
                          description = ''
                            A user's steam64 id.
                          '';
                        };
                        comment = lib.mkOption {
                          type = lib.types.nullOr lib.types.singleLineStr;
                          default = null;
                          description = ''
                            Optionally add a comment for the user in the Admin config.
                          '';
                        };
                      };
                    });
                  };
                };
              });
            };

            bans = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Manual bans to add to the server configuration.

                Basic Format: `<banned player steamid>:<unix timestamp of ban expiration>`.

                For additional details see
                https://squad.fandom.com/wiki/Server_Configuration#Bans_in_Bans.cfg.
              '';
            };

            customOptions = lib.mkOption {
              description = ''
                Custom options for mods in key-value format. Note that seed settings are considered mod
                settings for the purposes of Squad server configuration.

                See https://squad.fandom.com/wiki/Server_Configuration#Custom_Options for more
                details.
              '';
              default = { };
              type = lib.types.submodule {
                freeformType = settingsFormat.type;
                options = {
                  SeedPlayersThreshold = lib.mkOption {
                    type = lib.types.ints.positive;
                    default = 50;
                    description = ''
                      Amount of players needed to start the pre-live countdown.
                    '';
                  };
                  SeedMinimumPlayersToLive = lib.mkOption {
                    type = lib.types.ints.positive;
                    default = 45;
                    description = ''
                      After reaching the SeedPlayersThreshold, if some players disconect, but the current
                      player count stays at or above this value, don't stop the pre-live countdown. Should
                      be less than SeedPlayersThreshold to be considered enabled.
                    '';
                  };
                  SeedMatchLengthSeconds = lib.mkOption {
                    type = lib.types.ints.positive;
                    default = 21600;
                    description = ''
                      Match length of a seed in seconds.
                    '';
                  };
                  SeedInitialTickets = lib.mkOption {
                    type = lib.types.ints.positive;
                    default = 100;
                    description = ''
                      Initial tickets for both teams.
                    '';
                  };
                  SeedAllKitsAvailable = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    apply = (val: if val == true then 1 else 0);
                    description = ''
                      Enable or disable availability of all kits during seeding phase.
                    '';
                  };
                  SeedSecondsBeforeLive = lib.mkOption {
                    type = lib.types.float;
                    default = 60.0;
                    description = ''
                      Length of the pre-live countdown.
                    '';
                  };
                };
              };
            };

            excludedFactions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Exlude factions from the rotation.

                See https://squad.fandom.com/wiki/Server_Configuration#Excluded_Factions for more
                details.
              '';
            };

            excludedFactionSetups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Exlude specific faction setups from the rotation.

                See https://squad.fandom.com/wiki/Server_Configuration#Excluded_Faction_Setups for
                more details.
              '';
            };

            excludedLayers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Exclude layers from loading.

                See https://squad.fandom.com/wiki/Server_Configuration#Excluded_Layers for
                more details.
              '';
            };

            excludedLevels = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Exclude entire maps/levels from loading.

                See https://squad.fandom.com/wiki/Server_Configuration#Excluded_Levels for
                more details.
              '';
            };

            levelRotation = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Set rotation of maps/levels allowing any layer on those maps.

                See https://squad.fandom.com/wiki/Server_Configuration#Level_Rotation for
                more details.
              '';
            };

            layerRotation = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Set rotation of specific layers.

                See https://squad.fandom.com/wiki/Server_Configuration#Layer_Rotation for
                more details.
              '';
            };

            serverMessages = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                Server messages to show on a rotation based on the ServerMessageInterval.

                See
                https://squad.fandom.com/wiki/Server_Configuration#Server_Messages_in_ServerMessages.cfg
                for more details.
              '';
            };

            motd = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = ''
                Message to show to all players who join the server.

                See https://squad.fandom.com/wiki/Server_Configuration#Message_of_the_day_in_Motd.cfg
                for more details.
              '';
            };

            remoteAdminLists = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                The remote admin lists that the server will also pull from for admins.

                See
                https://squad.fandom.com/wiki/Server_Configuration#Remote_Admin_Lists_in_RemoteAdminListHosts.cfg
                for more details.
              '';
            };

            remoteBanLists = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              apply = lib.concatStringsSep "\n";
              default = [ ];
              description = ''
                The remote ban lists that the server will also pull from for bans.

                See
                https://squad.fandom.com/wiki/Server_Configuration#Remote_Ban_Lists_in_RemoteBanListHosts.cfg
                for more details.
              '';

            };

            server = {
              passwordFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = ''
                  The file to read the server password from. If this is set then the server will
                  require a password. Prefer this option over `ServerPassword`.
                '';
              };
              maxTickRate = lib.mkOption {
                type = lib.types.ints.positive;
                default = 35;
                description = ''
                  The max tick rate the server will run at. Recommended to use a tick rate of 35 (the
                  default).
                '';
              };
              settings = lib.mkOption {
                type = lib.types.submodule {
                  freeformType = settingsFormat.type;
                  options = {
                    ServerName = lib.mkOption {
                      type = lib.types.str;
                      default = "${name}";
                      description = ''
                        Server name of the server to show in the server browser.

                        Multiple servers MUST have unique names.
                      '';
                    };
                    ServerPassword = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = ''
                        The password required to join the server. If this is empty (defualt) then the
                        server will be joinable without a password. Prefer the
                        `config.server.passwordFile` option so the password is not copied into the Nix
                        Store.
                      '';
                    };
                    ShouldAdvertise = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = ''
                        Whether or not the server should appear in the server browser.
                      '';
                    };
                    IsLANMatch = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Set the server to LAN mode.
                      '';
                    };
                    MaxPlayers = lib.mkOption {
                      type = lib.types.ints.positive;
                      # By default most licensed servers allow up to 100 players.
                      default = 100;
                      description = ''
                        Set the player limit for the server.
                      '';
                    };
                    NumReservedSlots = lib.mkOption {
                      type = lib.types.ints.positive;
                      default = 2;
                      description = ''
                        Set the number of reserved slots for those with `reserve` perms in the admin list.
                      '';
                    };
                    PublicQueueLimit = lib.mkOption {
                      type = lib.types.addCheck lib.types.int (x: x >= -1);
                      default = 25;
                      description = ''
                        The limit on how many players can be queued to join the server.

                        If set to -1 then the queue is unlimited.
                      '';
                    };
                    MapRotationMode = lib.mkOption {
                      type = lib.types.enum [
                        "LevelList"
                        "LayerList"
                        "LevelList_Randomized"
                        "LayerList_Randomized"
                      ];
                      default = "LayerList";
                      description = ''
                        The map rotation mode to use. If set to LevelList, will use level rotation, if set
                        to LayerList, will use layer rotation. Suffixing with `_Randomized` will respect
                        the defined layers/levels, but not their ordering.

                        See https://squad.fandom.com/wiki/Server_Configuration#Map_Rotation_Modes for more
                        details.
                      '';
                    };
                    RandomizeAtStart = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      readOnly = true;
                      visible = false;
                      description = ''
                        Whether the Map/Layer rotations list should be randomized at start.

                        According to Squad Configs "DO NOT USE, MODDED WILL NOT WORK".
                      '';
                    };
                    UseVoteFactions = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      readOnly = true;
                      visible = false;
                      description = ''
                        Whether the Faction should be voted on at the end of a round.

                        At the time this was created, Squad's voting system does not work.
                      '';
                    };
                    UseVoteLevel = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      readOnly = true;
                      visible = false;
                      description = ''
                        Whether the level should be voted on at the end of a round.

                        At the time this was created, Squad's voting system does not work.
                      '';
                    };
                    UseVoteLayer = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      readOnly = true;
                      visible = false;
                      description = ''
                        Whether the layer should be voted on at the end of a round.

                        At the time this was created, Squad's voting system does not work.
                      '';
                    };
                    AllowTeamChanges = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = ''
                        Completely Allow or Disallow team changes to all players. Only users in the admin
                        config with `Level_Balance` can bypass this.
                      '';
                    };
                    PreventTeamChangeIfUnbalanced = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = ''
                        If disabled, players can always change teams regardless of the balance.
                      '';
                    };
                    NumPlayersDiffForTeamChanges = lib.mkOption {
                      type = lib.types.ints.unsigned;
                      default = 2;
                      description = ''
                        Maximum allowed difference in player count between teams. This takes into account
                        the team the player leaves and the team the player joins.
                      '';
                    };
                    RejoinSquadDelayAfterKick = lib.mkOption {
                      type = lib.types.ints.unsigned;
                      default = 180;
                      description = ''
                        Amount of time before a player kicked from a squad can rejoin that squad.
                      '';
                    };
                    RecordDemos = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Allow admins with `ClientDemos` permission to record demos. It's recommended to
                        leave this disabled as it can be used to cheat easily without a way to detect if
                        cheating is occuring.
                      '';
                    };
                    AllowPublicClientsToRecord = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Allow any playersto record demos. It's recommended to leave this disabled as it
                        can be used to cheat easily without a way to detect if cheating is occuring.
                      '';
                    };
                    ServerMessageInterval = lib.mkOption {
                      type = lib.types.ints.positive;
                      default = 1200;
                      description = ''
                        Interval between showing server messages.
                      '';
                    };
                    TKAutoKickEnabled = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = ''
                        Whether or not to kick players who exceed the `AutoTKBanNumberTKs` limit.

                        NOTE: Licensed servers MUST enable this option.
                      '';
                    };
                    AutoTKBanNumberTKs = lib.mkOption {
                      type = lib.types.ints.positive;
                      default = 10;
                      description = ''
                        How many TKs a player may have before being kicked.

                        NOTE: Licensed servers MUST set this option between 7 and 10 inclusive.
                      '';
                    };
                    AutoTKBanTime = lib.mkOption {
                      type = lib.types.ints.unsigned;
                      default = 300;
                      description = ''
                        How long to reject a player auto kicked for TKs from joining in seconds.

                        NOTE: Licensed servers MUST set this option to be more than 0.
                      '';
                    };
                    AllowDevProfiling = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = ''
                        Whether to allow Offword Industries Developers to be admins in the server.

                        NOTE: Licensed servers MUST enable this option.
                      '';
                    };
                    VehicleClaimingDisabled = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Whether to disable vehicle claiming.

                        NOTE: Licensed servers MUST disable this option.
                      '';
                    };
                    Tags = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      apply = lib.concatStringsSep " ";
                      description = ''
                        Tags to apply to the server to be shown in the server browser.

                        See https://squad.fandom.com/wiki/Server_Configuration#Tag_System for more details.
                      '';
                    };
                    Rules = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      apply = lib.concatStringsSep " ";
                      description = ''
                        Rules to apply to the server to be shown in the server browser.

                        See https://squad.fandom.com/wiki/Server_Configuration#Tag_System for more details.
                      '';
                    };
                  };
                };
                default = { };
                description = ''
                  Options to be defined in Server.cfg

                  See
                  https://squad.fandom.com/wiki/Server_Configuration#Server_Configuration_Settings_in_Server.cfg
                  for more details.
                '';
              };
            };

            license = {
              file = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = ''
                  A path to a file containing the server license. Prefer this over
                  `config.license.content` so the license text isn't copied into the Nix
                  store.
                '';
              };
              content = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = ''
                  The raw content of the license for the server. Prefer using the
                  `config.license.file` option over this as the content in this option will be copied
                  into the Nix store.
                '';
              };
            };
          };

        };
      }));
    };
  };

  config =
    let
      # Credit to https://github.com/mkaito/nixos-modded-minecraft-servers/tree/master.
      # A fair bit of the handling of the nested servers was based upon the code there.
      enabledServers = lib.filterAttrs (_: conf: conf.enable) cfg.servers;
      mkServerName = name: "squad-${replaceNonAlum "-" name}";
      eachEnabledServer = f: lib.mapAttrs' (name: config: lib.nameValuePair (mkServerName name) (f name config)) enabledServers;
      collectPorts = portType: lib.lists.flatten (lib.mapAttrsToList (_: serverConfig: serverConfig.${portType}) enabledServers);
      gamePorts = collectPorts "gamePort";
      queryPorts = collectPorts "queryPort";
      rconPorts = collectPorts "rconPort";
      beaconPorts = collectPorts "beaconPort";
      allPorts = gamePorts ++ queryPorts ++ rconPorts ++ beaconPorts;
    in
    {
      assertions = [
        {
          assertion = (lib.unique gamePorts) == gamePorts;
          message = ''
            Your Squad servers have overlapping game ports. Ensure the game ports are unique.
            Reminder: Squad uses the game port you define and `gamePort + 1`.

            Game Ports Found:
            ${builtins.toJSON gamePorts}
          '';
        }
        {
          assertion = (lib.unique queryPorts) == queryPorts;
          message = ''
            Your Squad servers have overlapping query ports. Ensure the query ports are unique.
            Reminder: Squad uses the query port you define and `queryPort + 1`.

            Query Ports Found:
            ${builtins.toJSON queryPorts}
          '';
        }
        {
          assertion = (lib.unique rconPorts) == rconPorts;
          message = ''
            Your Squad servers have overlapping rcon ports. Ensure the rcon ports are unique.

            Rcon Ports Found:
            ${builtins.toJSON rconPorts}
          '';
        }
        {
          assertion = (lib.unique beaconPorts) == beaconPorts;
          message = ''
            Your Squad servers have overlapping beacon ports. Ensure the beacon ports are unique.

            Rcon Ports Found:
            ${builtins.toJSON beaconPorts}
          '';
        }
        {
          assertion = (lib.unique allPorts) == allPorts;
          message = ''
            Your Squad servers have overlapping ports among game, query, rcon, and beacon ports.
            Ensure all ports are unique among all Squad servers.

            All Ports Found:
            ${builtins.toJSON allPorts}
          '';
        }
      ];

      networking.firewall = {
        allowedUDPPorts = beaconPorts ++ gamePorts ++ queryPorts ++ rconPorts;
        allowedTCPPorts = rconPorts ++ queryPorts;
      };

      systemd.services = (eachEnabledServer (name: cfg:
        let
          cfgs = {
            Admins = pkgs.writeText "Admins.cfg" cfg.config.admins;
            Bans = pkgs.writeText "Bans.cfg" cfg.config.bans;
            CustomOptions = settingsFormat.generate "CustomOptions.cfg" cfg.config.customOptions;
            ExcludedFactionSetups = pkgs.writeText "ExcludedFactionSetups.cfg" cfg.config.excludedFactionSetups;
            ExcludedFactions = pkgs.writeText "ExcludedFactions.cfg" cfg.config.excludedFactions;
            ExcludedLayers = pkgs.writeText "ExcludedLayers.cfg" cfg.config.excludedLayers;
            ExcludedLevels = pkgs.writeText "ExcludedLevels.cfg" cfg.config.excludedLevels;
            LayerRotation = pkgs.writeText "LayerRotation.cfg" cfg.config.layerRotation;
            LevelRotation = pkgs.writeText "LayerRotation.cfg" cfg.config.levelRotation;
            License = pkgs.writeText "License.cfg" cfg.config.license.content;
            MOTD = pkgs.writeText "MOTD.cfg" cfg.config.motd;
            Rcon = settingsFormat.generate "Rcon.cfg" cfg.config.rcon.settings;
            RemoteAdminListHosts = pkgs.writeText "RemoteAdminListHosts.cfg" cfg.config.remoteAdminLists;
            RemoteBanListHosts = pkgs.writeText "RemoteBanListHosts.cfg" cfg.config.remoteBanLists;
            Server = settingsFormat.generate "Server.cfg" cfg.config.server.settings;
            ServerMessages = pkgs.writeText "ServerMessages.cfg" cfg.config.serverMessages;
          };
        in
        {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            DynamicUser = true;
            StateDirectory = "${cfg.stateDir}";
            CacheDirectory = "${cfg.cacheDir}";
            StateDirectoryMode = "0700";
            LoadCredential = [ ]
              ++
              lib.optional
                (cfg.config.rcon.passwordFile != null)
                [ "SQUAD_RCON_PASSWORD_FILE:${cfg.config.rcon.passwordFile}" ]
              ++
              lib.optional
                (cfg.config.server.passwordFile != null)
                [ "SQUAD_SERVER_PASSWORD_FILE:${cfg.config.server.passwordFile}" ]
              ++
              lib.optional
                (cfg.config.license.file != null)
                [ "SQUAD_LICENSE_FILE:${cfg.config.license.file}" ];
            ExecStart =
              let
                server_dir = "/var/lib/${cfg.stateDir}";
              in
              pkgs.writeScript "start-squad-server" ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                # Install or update the server.
                cat <<-__EOS__
                ┌
                │ Installing/Updating Squad Server:
                │  Name -> '${cfg.config.server.settings.ServerName}'
                │  Path -> '${server_dir}'
                │
                │ This may take a while as the server will need to download any required files if they
                │ weren't downloaded previously.
                └
                __EOS__

                HOME="/var/cache/${cfg.cacheDir}" ${pkgs.steamcmd}/bin/steamcmd \
                  +force_install_dir "${server_dir}" \
                  +login anonymous \
                  +app_update 403240 validate \
                  +quit

                # Install mods if any are defined
                ${let
                  workshop_id = "393380";
                  mod_install_dir = "${server_dir}/steamapps/workshop/content/${workshop_id}";
                in
                 lib.optionalString (builtins.length (cfg.mods) > 0) ''
                cat <<-__EOS__
                ┌
                │ Installing Mods for Squad Server:
                │  Mod IDs -> ${builtins.toString cfg.mods}
                │
                │ This may take a while as the server will need to download any required files if they
                │ weren't downloaded previously.
                └
                __EOS__
                read -ra SQUAD_MODS <<< "${builtins.toString cfg.mods}"
                for mod in "''${SQUAD_MODS[@]}"; do
                  printf "==== Attempting to install mod: '%s' ====\n" "$mod"
                  # We have to do this attempt stuff because steamcmd can timeout while downloading
                  # large mods. By making another attempt steamcmd will continue downloading from
                  # where it left off. From experience it should need no more than 5 attempts. Any
                  # more than that and either steam is getting DoS'd, you've been rate limited
                  # completely, your network is *way* too slow, or nuclear war has been declared and
                  # all that remains of AWS east is a crater.
                  REMAINING_ATTEMPTS=5
                  until HOME="/var/cache/${cfg.cacheDir}" ${pkgs.steamcmd}/bin/steamcmd \
                    +force_install_dir "${mod_install_dir}/$mod" \
                    +login anonymous \
                    +workshop_download_item  "${workshop_id}" "$mod" \
                    +quit; do
                      (( REMAINING_ATTEMPTS-- ))
                      printf "Did not fully download squad mod '%s', remaining attempts: '%s'\n" \
                        "$mod" "$REMAINING_ATTEMPTS"
                      if (( REMAINING_ATTEMPTS == 0 )); then
                        printf "#### Too many attempts while downloading a mod! Failed to download the mod: '%s' ####\n" "$mod"
                        exit 1
                      fi
                    done
                    ln -sf "${mod_install_dir}/$mod" "${server_dir}/SquadGame/Plugins/Mods/$mod"
                    printf "#### Successfully installed mod: '%s' ####\n" "$mod"
                done
                ''}

                cat <<-__EOS__
                ┌
                │ Patching Squad Binaries
                └
                __EOS__

                find "${server_dir}/" \
                  -type f \
                  -executable \
                  -printf "patchelf: Attempting to patch '%p'\n" \
                  -exec \
                  ${pkgs.patchelf}/bin/patchelf --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 {} \;

                cat <<-__EOS__
                ┌
                │ Generating Configurations
                └
                __EOS__

                pushd ./SquadGame/ServerConfig >/dev/null 2>&1

                ${lib.attrsets.foldlAttrs (acc: name: path: ''
                ${acc}
                # Handle the ${name} configuration
                printf "Generating the '%s' configuration file.\n" "${name}.cfg"
                cp -f "${path}" ./"${name}.cfg"
                '') "" cfgs}

                ${lib.optionalString (cfg.config.server.passwordFile != null) ''
                ## Handle secrets for the `Server.cfg` file ##
                # Safely load the server password outside of the nix store
                sed -i -e 's/^ServerPassword=.*$/ServerPassword='"$(${pkgs.systemd}/bin/systemd-creds cat SQUAD_SERVER_PASSWORD_FILE)"'/g' ./Server.cfg
                ''}

                # Correct the permissions for the Squad Server cfgs. When the Squad Server is first
                # installed it will include the configs by default with an overly open CHMOD.
                chmod 0400 *.cfg

                ${lib.optionalString (cfg.config.rcon.passwordFile != null) ''
                ## Handle secrets for the `Rcon.cfg` file ##
                # Safely load the rcon password outside of the nix store
                sed -i -e 's/^Password=.*$/Password='"$(${pkgs.systemd}/bin/systemd-creds cat SQUAD_RCON_PASSWORD_FILE)"'/g' ./Rcon.cfg
                ''}

                ${lib.optionalString (cfg.config.license.file != null) ''
                ## Handle secrets for the `License.cfg` file ##
                # Safely load the license outside of the nix store
                printf "%s" "$(${pkgs.systemd}/bin/systemd-creds cat SQUAD_LICENSE_FILE)" > ./License.cfg
                ''}

                popd >/dev/null 2>&1

                cat <<-__EOS__
                ┌
                │ Starting Squad Server:
                │   Name -> '${cfg.config.server.settings.ServerName}
                │   Path -> '${server_dir}'
                └
                __EOS__

                LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib" ./SquadGameServer.sh \
                  Port=${builtins.toString cfg.gamePort} \
                  QueryPort=${builtins.toString cfg.queryPort} \
                  FIXEDMAXTICKRATE=${builtins.toString cfg.config.server.maxTickRate} \
                  FIXEDMAXPLAYERS=${builtins.toString cfg.config.server.settings.MaxPlayers} \
                  beaconport=${builtins.toString cfg.beaconPort}
              '';
            WorkingDirectory = "/var/lib/${cfg.stateDir}";
          };
        }));
    };
}






