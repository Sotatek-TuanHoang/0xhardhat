pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "./interfaces/ITestFeature.sol";
import "../fixins/FixinCommon.sol";
import "../migrations/LibMigrate.sol";
import "./interfaces/IFeature.sol";

contract TestFeature is
    IFeature,
    ITestFeature,
    FixinCommon
{

    string public constant override FEATURE_NAME = "Test";
    /// @dev Version of this feature.
    uint256 public immutable override FEATURE_VERSION = _encodeVersion(1, 1, 1);

    constructor() 
        public
        FixinCommon()
    {
    }

    function hello() public pure override returns (string memory) {
        return "hlnf";
    }

    function migrate()
    external
    override
    returns (bytes4 success)
    {
        // _registerFeatureFunction(this.setRoles.selector);
        _registerFeatureFunction(this.hello.selector);
        return LibMigrate.MIGRATE_SUCCESS;
    }


}
