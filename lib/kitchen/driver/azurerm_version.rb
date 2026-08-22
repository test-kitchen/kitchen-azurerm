module Kitchen
  module Driver
    # Version of the kitchen-azurerm gem.
    #
    # Kept in its own file so the gemspec can read it without loading the
    # driver and, with it, the whole Azure SDK.
    #
    # @return [String]
    AZURERM_VERSION = "1.13.6".freeze
  end
end
