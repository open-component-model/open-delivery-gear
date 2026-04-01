secrets:
  bdba:
    primary:
      api_url: ${bdba_url}
      group_ids:
        - 2907
      token: '${bdba_token}'
  blackduck:
    ctp:
      api_url: ${blackduck_ctp_url}
      group_id: 86cb71af-4bc8-4fbe-beed-4e5731625620
      token: '${blackduck_ctp_token}'
    foss:
      api_url: ${blackduck_foss_url}
      group_id: f199b865-2b0f-412a-bc11-a190b8e2ee02
      token: '${blackduck_foss_token}'
  delivery-db:
    primary:
      username: postgres
      password: '${delivery_db_password}'
  github-app:
    github-com:
      api_url: https://api.github.com
      app_id: 1725627
      mappings:
        - installation_id: 79146296
          org: open-component-model
      private_key: |
% for line in github_app_private_key.splitlines():
        ${line}
% endfor
  oauth-cfg:
    github-com:
      name: GitHub
      type: github
      api_url: https://api.github.com
      client_id: Iv23lilcEx1MzFcsEsNC
      client_secret: '${oauth_cfg_client_secret}'
      role_bindings:
        - roles:
            - admin
          subjects:
            - name: open-component-model/odg-maintainers
              type: github-team
        - roles:
            - writer
          subjects:
            - name: open-delivery-gear
              type: github-app
        - roles:
            - reader
          subjects:
            - name: open-component-model
              type: github-org
  signing-cfg:
    primary:
      id: 517c9ea5-b84c-4b33-9c89-3f4e6d13720b
      algorithm: RS256
      private_key: |
% for line in signing_cfg_private_key.splitlines():
        ${line}
% endfor
      public_key: |
% for line in signing_cfg_public_key.splitlines():
        ${line}
% endfor
