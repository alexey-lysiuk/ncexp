// Copyright (C) 2013-2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include "VFSDeclarations.h"
#include "VFSConfiguration.h"

class VFSPath
{
public:
    VFSPath();
    VFSPath(const VFSHostPtr &_host, std::string _path);
    VFSPath(VFSHost &_host, std::string _path);
    VFSPath(const VFSPath &_rhs) = default;
    VFSPath(VFSPath &&_rhs) = default;
    
    const VFSHostPtr& Host() const noexcept;
    const std::string&Path() const noexcept;
    operator          bool() const noexcept;
    void              Reset();
    
    VFSPath &operator=(const VFSPath &_rhs) = default;
    VFSPath &operator=(VFSPath &&_rhs) = default;
    
private:
    VFSHostPtr  m_Host;
    std::string m_Path;
};

bool operator  <(const VFSPath& _lhs, const VFSPath& _rhs) noexcept;
bool operator ==(const VFSPath& _lhs, const VFSPath& _rhs) noexcept;
bool operator !=(const VFSPath& _lhs, const VFSPath& _rhs) noexcept;

class VFSPathStack
{
public:
    struct Part
    {
        Part() = default;
        Part(VFSHost &_host);
        
        const char* fs_tag; // this tag is redundant since configuration already able to provide it
        std::string junction;
        std::weak_ptr<VFSHost> host;
        VFSConfiguration configuration;

        /**
         * operation== performs fast comparison by ptrs.
         */
        bool operator==(const Part&_r) const;
        bool operator!=(const Part&_r) const;
        
        /**
         * Will compare parts without respect to host ptr and will compare options by it's content.
         */
        bool weak_equal(const Part&_r) const;
    };
    
    VFSPathStack();
    VFSPathStack(const VFSHostPtr &_vfs, const std::string &_path);
    
    bool operator==(const VFSPathStack& _r) const;
    bool operator!=(const VFSPathStack& _r) const;
    const Part& operator[](size_t _n) const;
    bool empty() const;
    size_t size() const;
    const Part& back() const;
    const std::string& path() const;
    bool weak_equal(const VFSPathStack&_r) const;
    std::string verbose_string() const;
private:
    friend struct std::hash<VFSPathStack>;
    std::vector<Part>    m_Stack;
    std::string          m_Path;
};

// calculating hash() of VFSPathStack
template<>
struct std::hash<VFSPathStack>
{
    typedef VFSPathStack argument_type;
    typedef std::size_t value_type;
    value_type operator()(argument_type const& _v) const;
};
